#!/bin/bash
set -euo pipefail

: "${CTF_SECRET:?CTF_SECRET must be set}"
export CTF_SECRET

mkdir -p /var/log/supervisor /opt/backoffice/secret /root/secret

getflag() { /opt/venv/bin/python3 -c "import sys; sys.path.insert(0,'/opt/shared'); from generate_flags import flag_for; print(flag_for('$CTF_SECRET', $1))"; }
getfrag() { /opt/venv/bin/python3 -c "import sys; sys.path.insert(0,'/opt/shared'); from generate_flags import fragment_for; print(fragment_for('$CTF_SECRET', '$1'))"; }

# Reachable only via the pickle-deserialization RCE (app.py's /api/process).
getflag 7 > /opt/backoffice/secret/flag7.txt
getflag 8 > /opt/backoffice/secret/flag8.txt
chown svc:svc /opt/backoffice/secret/*.txt
chmod 600 /opt/backoffice/secret/*.txt

# Reachable only after the SUID-awk privesc to root.
getflag 9 > /root/secret/flag9.txt
getfrag B > /root/secret/fragmentB.txt
chmod 600 /root/secret/*.txt

echo "[entrypoint] Back Office ready."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/ctf.conf
