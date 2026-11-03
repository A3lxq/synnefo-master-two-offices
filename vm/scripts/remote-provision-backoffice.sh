#!/usr/bin/env bash
# remote-provision-backoffice.sh — deploys the Back Office half of the
# Master (Two Offices) CTF box onto an already-booted Ubuntu 24.04
# guest (run over SSH as ctfbuilder, with sudo). Native build: real
# Flask app via systemd, running as an unprivileged account, with a
# SUID `find` privesc. No Docker anywhere. Public, so never hardcode
# the release secret here -- it must only ever arrive via the SSH
# session's own environment.
set -euo pipefail

: "${RELEASE_SECRET:?RELEASE_SECRET must be passed in (never hardcode it here -- this script is public)}"

echo "== Back Office: packages & venv =="
sudo apt-get install -y -qq python3-venv >/dev/null 2>&1 || true
sudo python3 -m venv /opt/venv
sudo /opt/venv/bin/pip install -q --no-cache-dir flask==3.1.0

sudo mkdir -p /opt/shared /opt/app /opt/backoffice/secret /root/secret

echo "== Back Office: shared flag module =="
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

getflag() { /opt/venv/bin/python3 -c "import sys; sys.path.insert(0,'/opt/shared'); from generate_flags import flag_for; print(flag_for('$RELEASE_SECRET', $1))"; }
getfrag() { /opt/venv/bin/python3 -c "import sys; sys.path.insert(0,'/opt/shared'); from generate_flags import fragment_for; print(fragment_for('$RELEASE_SECRET', '$1'))"; }

echo "== Back Office: app.py =="
sudo tee /opt/app/app.py >/dev/null <<'PYEOF'
"""
Back Office -- the branch's internal-only workstation. Flask, port
6000. Never reachable from the host or from anywhere except Front
Desk's internal NIC -- lateral movement / pivoting is the whole point.

INTENTIONALLY VULNERABLE: insecure deserialization (Python pickle) in
/api/process.
"""
import base64
import os
import pickle
import sys

from flask import Flask, request, Response

sys.path.insert(0, "/opt/shared")
from generate_flags import flag_for  # noqa: E402

SECRET = os.environ["CTF_SECRET"]
app = Flask(__name__)


def flag(n):
    return flag_for(SECRET, n)


@app.route("/")
def index():
    return f"""Back Office internal tools API
------------------------------
note: {flag(6)}

POST base64-encoded pickled job data to /api/process.
"""


@app.route("/ops-portal")
def ops_portal_decoy():
    return "Ops portal is being migrated. Use the main API for now.\n"


@app.route("/api/process", methods=["POST"])
def process():
    data = request.form.get("data", "")
    try:
        obj = pickle.loads(base64.b64decode(data))
    except Exception as e:
        return Response(f"error: {e}\n", status=400)
    return Response(f"processed: {obj!r}\n")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=6000)
PYEOF

echo "== Back Office: accounts =="
# svc runs the app (unprivileged -- the pickle RCE alone must NOT hand
# over root). ops is a honeypot: a real account, visible in
# /etc/passwd, with no valid credential or path to it at all.
if ! id svc >/dev/null 2>&1; then
  sudo useradd -m -s /usr/sbin/nologin svc
fi
if ! id ops >/dev/null 2>&1; then
  sudo useradd -m -s /bin/bash ops
fi

echo "== Back Office: systemd service (runs as svc, not root) =="
sudo tee /etc/systemd/system/backoffice-app.service >/dev/null <<EOF
[Unit]
Description=Back Office Flask app
After=network.target

[Service]
User=svc
Environment=CTF_SECRET=$RELEASE_SECRET
ExecStart=/opt/venv/bin/python3 /opt/app/app.py
WorkingDirectory=/opt/app
Restart=always

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now backoffice-app.service

echo "== Back Office: secrets reachable only via the pickle RCE =="
getflag 7 | sudo tee /opt/backoffice/secret/flag7.txt >/dev/null
getflag 8 | sudo tee /opt/backoffice/secret/flag8.txt >/dev/null
sudo chown svc:svc /opt/backoffice/secret/flag7.txt /opt/backoffice/secret/flag8.txt
sudo chmod 600 /opt/backoffice/secret/flag7.txt /opt/backoffice/secret/flag8.txt

echo "== Back Office: root's own secrets, reachable only via the SUID find privesc =="
getflag 9 | sudo tee /root/secret/flag9.txt >/dev/null
getfrag B | sudo tee /root/secret/fragmentB.txt >/dev/null
sudo chmod 600 /root/secret/flag9.txt /root/secret/fragmentB.txt

echo "== Back Office: SUID find privesc (GTFOBins -exec -- verified reliable;"
echo "   Debian/Ubuntu's mawk drops privileges in its own system() builtin,"
echo "   and modern perl no longer supports setuid scripts at all) =="
REAL_FIND=$(readlink -f /usr/bin/find)
sudo chmod u+s "$REAL_FIND"
ls -la "$REAL_FIND"

echo "[remote-provision-backoffice] Back Office ready."
