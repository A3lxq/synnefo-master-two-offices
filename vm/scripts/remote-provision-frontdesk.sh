#!/usr/bin/env bash
# remote-provision-frontdesk.sh — deploys the Front Desk half of the
# Master (Two Offices) CTF box onto an already-booted Ubuntu 24.04
# guest (run over SSH as ctfbuilder, with sudo). Native build: real
# Flask app via systemd, real cron, real openssh-server. No Docker
# anywhere. Public, so never hardcode the release secret here -- it
# must only ever arrive via the SSH session's own environment.
set -euo pipefail

: "${RELEASE_SECRET:?RELEASE_SECRET must be passed in (never hardcode it here -- this script is public)}"

CLERK_PASSWORD="Cl3rk-Front2024!"   # only ever disclosed via the flag 4 XXE read

echo "== Front Desk: packages & venv =="
sudo apt-get install -y -qq python3-venv >/dev/null 2>&1 || true
sudo python3 -m venv /opt/venv
sudo /opt/venv/bin/pip install -q --no-cache-dir flask==3.1.0 lxml==5.3.0 cryptography==43.0.3

sudo mkdir -p /opt/shared /opt/app /opt/frontdesk/secret /root/secret /opt/admin/bin

echo "== Front Desk: shared flag/crypto modules =="
sudo tee /opt/shared/generate_flags.py >/dev/null <<'EOF'
import hmac
import hashlib

BOX_ID = "master-two-offices"


def flag_for(secret: str, n: int) -> str:
    digest = hmac.new(secret.encode(), f"{BOX_ID}:{n}".encode(), hashlib.sha256).hexdigest()
    return f"HLC{{{digest[:10]}}}"


def fragment_for(secret: str, which: str) -> str:
    digest = hmac.new(secret.encode(), f"{BOX_ID}:fragment:{which}".encode(), hashlib.sha256).hexdigest()
    return digest[:20]
EOF

sudo tee /opt/shared/flagcrypto.py >/dev/null <<'EOF'
#!/usr/bin/env python3
"""
flagcrypto.py -- ships to players unchanged. scrypt for password-based
key derivation, AES-256-GCM for authenticated encryption.

File format (binary): b"HLCX1" + 16-byte salt + 12-byte nonce + ciphertext||tag

Usage:
    python3 flagcrypto.py encrypt <passphrase> <in-file> <out-file.enc>
    python3 flagcrypto.py decrypt <passphrase> <in-file.enc> <out-file|->
"""
import sys

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.scrypt import Scrypt

MAGIC = b"HLCX1"
SALT_LEN = 16
NONCE_LEN = 12
KEY_LEN = 32


def _derive_key(passphrase: str, salt: bytes) -> bytes:
    kdf = Scrypt(salt=salt, length=KEY_LEN, n=2**14, r=8, p=1)
    return kdf.derive(passphrase.encode("utf-8"))


def encrypt_bytes(passphrase: str, plaintext: bytes) -> bytes:
    import os
    salt = os.urandom(SALT_LEN)
    nonce = os.urandom(NONCE_LEN)
    key = _derive_key(passphrase, salt)
    ct = AESGCM(key).encrypt(nonce, plaintext, None)
    return MAGIC + salt + nonce + ct


def decrypt_bytes(passphrase: str, blob: bytes) -> bytes:
    if not blob.startswith(MAGIC):
        raise ValueError("Not a recognized flagcrypto file (bad magic).")
    rest = blob[len(MAGIC):]
    salt, nonce, ct = rest[:SALT_LEN], rest[SALT_LEN:SALT_LEN + NONCE_LEN], rest[SALT_LEN + NONCE_LEN:]
    key = _derive_key(passphrase, salt)
    return AESGCM(key).decrypt(nonce, ct, None)


if __name__ == "__main__":
    if len(sys.argv) != 5 or sys.argv[1] not in ("encrypt", "decrypt"):
        print(__doc__)
        sys.exit(1)
    mode, passphrase, infile, outfile = sys.argv[1:5]
    with open(infile, "rb") as f:
        data = f.read()
    result = encrypt_bytes(passphrase, data) if mode == "encrypt" else decrypt_bytes(passphrase, data)
    if outfile == "-":
        sys.stdout.buffer.write(result)
    else:
        with open(outfile, "wb") as f:
            f.write(result)
EOF

getflag() { /opt/venv/bin/python3 -c "import sys; sys.path.insert(0,'/opt/shared'); from generate_flags import flag_for; print(flag_for('$RELEASE_SECRET', $1))"; }
getfrag() { /opt/venv/bin/python3 -c "import sys; sys.path.insert(0,'/opt/shared'); from generate_flags import fragment_for; print(fragment_for('$RELEASE_SECRET', '$1'))"; }

echo "== Front Desk: app.py =="
sudo tee /opt/app/app.py >/dev/null <<'PYEOF'
"""
Front Desk -- the regional branch's public-facing workstation. Flask,
port 5000 (published). INTENTIONALLY VULNERABLE: XXE in the schedule
importer. This host also serves final.enc from the very start (teased
upfront) -- it can't be decrypted until you've rooted BOTH hosts in this
box and combined what each one gives you.
"""
import os
import sys

from flask import Flask, request, Response
from lxml import etree

sys.path.insert(0, "/opt/shared")
from generate_flags import flag_for  # noqa: E402

SECRET = os.environ["CTF_SECRET"]
app = Flask(__name__)


def flag(n):
    return flag_for(SECRET, n)


@app.route("/")
def index():
    return f"""<!DOCTYPE html><html><head><title>Front Desk</title></head><body>
    <!-- {flag(1)} -->
    <h1>Halcyon Regional Branch — Front Desk</h1>
    <!-- staff login at /login, schedule importer at /import-schedule -->
    <p>Everything your branch needs, in one portal. See
    <a href="/final.enc">final.enc</a> — the last piece of this case file,
    available from day one. You'll need more than this page to open it.</p>
    </body></html>"""


@app.route("/login", methods=["GET", "POST"])
def login():
    error = ""
    if request.method == "POST":
        u = request.form.get("username", "")
        p = request.form.get("password", "")
        if u == "branch_staff" and p == "branch2024":
            return f"<h2>Welcome back.</h2><p>{flag(2)}</p>"
        error = "Invalid credentials."
    return f"""<!DOCTYPE html><html><body>
    <h2>Staff Login</h2>
    <p style="color:red">{error}</p>
    <form method="post">
      Username: <input name="username"><br>
      Password: <input name="password" type="password"><br>
      <button type="submit">Log in</button>
    </form></body></html>"""


@app.route("/import-schedule", methods=["GET", "POST"])
def import_schedule():
    if request.method == "GET":
        return """<!DOCTYPE html><html><body>
        <h2>Import Shipment Schedule (XML)</h2>
        <p>POST raw XML as the request body, Content-Type: application/xml.
        Example: &lt;schedule&gt;&lt;name&gt;Week 12&lt;/name&gt;&lt;/schedule&gt;</p>
        </body></html>"""
    parser = etree.XMLParser(resolve_entities=True, no_network=False, load_dtd=True)
    try:
        tree = etree.fromstring(request.data, parser)
        name = tree.findtext("name") or "(no name field)"
        return Response(f"Schedule imported: {name}\n", mimetype="text/plain")
    except Exception as e:
        return Response(f"Import failed: {e}\n", status=400, mimetype="text/plain")


@app.route("/admin")
def admin_decoy():
    return Response("Not implemented yet. Ticket IT-2290.\n", status=501)


@app.route("/final.enc")
def final_enc():
    try:
        with open("/opt/frontdesk/final.enc", "rb") as f:
            return Response(f.read(), mimetype="application/octet-stream")
    except Exception as e:
        return Response(f"not ready: {e}", status=404)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
PYEOF

echo "== Front Desk: systemd service =="
sudo tee /etc/systemd/system/frontdesk-app.service >/dev/null <<EOF
[Unit]
Description=Front Desk Flask app
After=network.target

[Service]
Environment=CTF_SECRET=$RELEASE_SECRET
ExecStart=/opt/venv/bin/python3 /opt/app/app.py
WorkingDirectory=/opt/app
Restart=always

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now frontdesk-app.service

echo "== Front Desk: XXE targets =="
getflag 3 | sudo tee /opt/frontdesk/secret/flag3.txt >/dev/null
sudo tee /opt/frontdesk/secret/creds.txt >/dev/null <<EOF
# leftover from provisioning -- clerk's SSH password, never rotated
clerk:$CLERK_PASSWORD
EOF
sudo tee /opt/frontdesk/secret/old_backup.txt >/dev/null <<'EOF'
rotated after the migration, don't bother -- these work nowhere:
branch_admin:Adm1n-Legacy-99
EOF
sudo chmod 644 /opt/frontdesk/secret/flag3.txt /opt/frontdesk/secret/creds.txt /opt/frontdesk/secret/old_backup.txt

echo "== Front Desk: clerk account =="
if ! id clerk >/dev/null 2>&1; then
  sudo useradd -m -s /bin/bash clerk
fi
echo "clerk:$CLERK_PASSWORD" | sudo chpasswd
getflag 4 | sudo tee /home/clerk/flag4.txt >/dev/null
sudo chown clerk:clerk /home/clerk/flag4.txt
sudo chmod 600 /home/clerk/flag4.txt

sudo tee /etc/ssh/sshd_config.d/90-clerk-password-auth.conf >/dev/null <<'EOF'
Match User clerk
    PasswordAuthentication yes
EOF

echo "== Front Desk: PATH-hijack cron privesc =="
sudo chmod 1777 /opt/admin/bin
sudo tee /opt/admin/daily_report.sh >/dev/null <<'EOF'
#!/bin/bash
# Daily branch report helper (auto-generated, don't edit by hand).
backup-helper
EOF
sudo chmod 755 /opt/admin/daily_report.sh
sudo chown root:root /opt/admin/daily_report.sh

sudo tee /etc/cron.d/daily-report >/dev/null <<'EOF'
SHELL=/bin/bash
PATH=/opt/admin/bin:/usr/bin:/bin
* * * * * root /opt/admin/daily_report.sh >> /var/log/daily-report.log 2>&1
EOF
sudo chmod 644 /etc/cron.d/daily-report
sudo touch /var/log/daily-report.log
sudo chmod 644 /var/log/daily-report.log
sudo systemctl restart cron

echo "== Front Desk: root's own secrets (reachable only via the cron privesc) =="
F5=$(getflag 5)
FRAG_A=$(getfrag A)
echo "$F5" | sudo tee /root/secret/flag5.txt >/dev/null
echo "$FRAG_A" | sudo tee /root/secret/fragmentA.txt >/dev/null
sudo tee /root/secret/backoffice_notes.txt >/dev/null <<'EOF'
Reminder to self: the back-office workstation ("backoffice" on this
branch's internal network) isn't reachable from outside this office at
all -- that's intentional. If you're reading this from a shell on THIS
box, you can reach it directly though. It runs its own internal tools
API; nothing about its credentials is written down here on purpose.
EOF
sudo chmod 600 /root/secret/flag5.txt /root/secret/fragmentA.txt /root/secret/backoffice_notes.txt

echo "== Front Desk: final.enc (both fragments derivable from the secret alone) =="
FRAG_B=$(getfrag B)
F10=$(getflag 10)
echo -n "$F10" > /tmp/flag10_plain.txt
/opt/venv/bin/python3 /opt/shared/flagcrypto.py encrypt "${FRAG_A}${FRAG_B}" /tmp/flag10_plain.txt /tmp/final.enc
rm -f /tmp/flag10_plain.txt
sudo mv /tmp/final.enc /opt/frontdesk/final.enc
sudo chmod 644 /opt/frontdesk/final.enc

echo "== Front Desk: /etc/hosts entry for the internal link =="
if ! grep -q '^10\.10\.10\.2 backoffice' /etc/hosts; then
  echo "10.10.10.2 backoffice" | sudo tee -a /etc/hosts >/dev/null
fi

echo "== Front Desk: restart sshd (clean, no orphaned listeners) =="
sudo pkill -9 -f 'sshd: /usr/sbin/sshd -D \[listener\]' 2>/dev/null || true
sleep 1
sudo systemctl restart ssh

echo "[remote-provision-frontdesk] Front Desk ready."
