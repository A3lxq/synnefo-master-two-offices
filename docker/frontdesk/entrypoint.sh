#!/bin/bash
set -euo pipefail

: "${CTF_SECRET:?CTF_SECRET must be set}"
export CTF_SECRET

CLERK_PASSWORD="Cl3rk-Front2024!"   # only ever disclosed via the flag 4 XXE read

mkdir -p /var/log/supervisor /opt/frontdesk/secret /root/secret /opt/admin/bin

getflag() { /opt/venv/bin/python3 -c "import sys; sys.path.insert(0,'/opt/shared'); from generate_flags import flag_for; print(flag_for('$CTF_SECRET', $1))"; }
getfrag() { /opt/venv/bin/python3 -c "import sys; sys.path.insert(0,'/opt/shared'); from generate_flags import fragment_for; print(fragment_for('$CTF_SECRET', '$1'))"; }

# --- XXE targets -----------------------------------------------------------
getflag 3 > /opt/frontdesk/secret/flag3.txt
cat > /opt/frontdesk/secret/creds.txt <<EOF
# leftover from provisioning -- clerk's SSH password, never rotated
clerk:$CLERK_PASSWORD
EOF
# Honeypot: a plausible-sounding file an XXE-reading player might try
# next, with explicitly inert credentials.
cat > /opt/frontdesk/secret/old_backup.txt <<'EOF'
rotated after the migration, don't bother -- these work nowhere:
branch_admin:Adm1n-Legacy-99
EOF
chmod 644 /opt/frontdesk/secret/flag3.txt /opt/frontdesk/secret/creds.txt /opt/frontdesk/secret/old_backup.txt

# --- clerk account -----------------------------------------------------------
echo "clerk:$CLERK_PASSWORD" | chpasswd
getflag 4 > /home/clerk/flag4.txt
chown clerk:clerk /home/clerk/flag4.txt
chmod 600 /home/clerk/flag4.txt

# --- PATH-hijack privesc (Stage 5): a root cron job with an insecure PATH --
# /opt/admin/bin is world-writable and listed BEFORE /usr/bin in this
# cron job's own PATH -- clerk can drop a same-named binary there and
# have root's cron execute it within a minute.
chmod 1777 /opt/admin/bin   # world-writable (sticky bit doesn't fix the real bug: PATH order)
cat > /opt/admin/daily_report.sh <<'EOF'
#!/bin/bash
# Daily branch report helper (auto-generated, don't edit by hand).
backup-helper
EOF
chmod 755 /opt/admin/daily_report.sh
chown root:root /opt/admin/daily_report.sh

cat > /etc/cron.d/daily-report <<'EOF'
SHELL=/bin/bash
PATH=/opt/admin/bin:/usr/bin:/bin
* * * * * root /opt/admin/daily_report.sh >> /var/log/daily-report.log 2>&1
EOF
chmod 644 /etc/cron.d/daily-report
touch /var/log/daily-report.log && chmod 644 /var/log/daily-report.log

# --- root's own secrets, only reachable via the PATH-hijack privesc --------
F5=$(getflag 5)
FRAG_A=$(getfrag A)
cat > /root/secret/flag5.txt <<EOF
$F5
EOF
cat > /root/secret/fragmentA.txt <<EOF
$FRAG_A
EOF
cat > /root/secret/backoffice_notes.txt <<'EOF'
Reminder to self: the back-office workstation ("backoffice" on this
branch's internal network) isn't reachable from outside this office at
all -- that's intentional. If you're reading this from a shell on THIS
box, you can reach it directly though. It runs its own internal tools
API; nothing about its credentials is written down here on purpose.
EOF
chmod 600 /root/secret/*.txt

# --- final.enc: both fragments are derivable from CTF_SECRET alone, so
# this can be built now, even though it's unopenable until a player has
# rooted both hosts and found both fragments themselves. ---
FRAG_B=$(getfrag B)
F10=$(getflag 10)
echo -n "$F10" > /tmp/flag10_plain.txt
/opt/venv/bin/python3 /opt/shared/flagcrypto.py encrypt "${FRAG_A}${FRAG_B}" /tmp/flag10_plain.txt /opt/frontdesk/final.enc
rm -f /tmp/flag10_plain.txt
chmod 644 /opt/frontdesk/final.enc

ssh-keygen -A >/dev/null 2>&1 || true

echo "[entrypoint] Front Desk ready."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/ctf.conf
