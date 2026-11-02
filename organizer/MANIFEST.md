# Organizer manifest — Two Offices (Master)

Keep this file (and this whole `organizer/` directory) off any
player-facing host. Flag *values* are never written here — re-derive them
from the deployment's `CTF_SECRET` (HMAC-SHA256("master-two-offices:N",
secret), first 10 hex chars, wrapped `HLC{...}`). Fragments A/B use the
same HMAC with `:fragment:A` / `:fragment:B`, first 20 hex chars.

Two hosts: **Front Desk** (published to the host) and **Back Office**
(internal-only — no published ports at all, reachable only by pivoting
through a shell on Front Desk).

| # | Host | Difficulty | Concept taught | Primary tool(s) | Where it lives |
|---|---|---|---|---|---|
| 1 | Front Desk | Easy | Reading page source | curl/browser | HTML comment on `/` |
| 2 | Front Desk | Easy | Default/weak credentials | curl/browser | `branch_staff`/`branch2024` on `/login` |
| 3 | Front Desk | Medium | XXE (XML External Entity) | Burp/curl, hand-crafted XML | `/import-schedule` -> `file:///opt/frontdesk/secret/flag3.txt` |
| 4 | Front Desk | Medium | XXE used again, then SSH | same, then `ssh` | `creds.txt` via XXE -> `clerk`'s password |
| 5 | Front Desk | Medium/Hard | PATH-hijack privilege escalation | manual enumeration of cron + PATH | `/etc/cron.d/daily-report`'s insecure `PATH=/opt/admin/bin:...` |
| 6 | Back Office | Easy (once pivoted) | Lateral movement / internal recon | `curl` from the clerk SSH session | `backoffice:6000/` (Docker-internal DNS, never published) |
| 7 | Back Office | Hard | Insecure deserialization (Python pickle) RCE | hand-crafted pickle `__reduce__` payload | `/api/process` |
| 8 | Back Office | Hard | Same RCE, a second file | same | `/opt/backoffice/secret/flag8.txt` |
| 9 | Back Office | Hardest | SUID `find` privilege escalation | GTFOBins `find -exec`, via the RCE | `/root/secret/flag9.txt` + `fragmentB.txt` |
| 10 | Front Desk | Capstone | Combining two independently-found secrets | `flagcrypto.py` (ships to players) | `/final.enc`, key = fragmentA + fragmentB |

## Honeypots (never flag-shaped, cost time only)
- Front Desk `/admin` — a plausible path, 501 response, nothing behind it.
- Front Desk XXE target `old_backup.txt` — explicitly inert decoy creds.
- Back Office `/ops-portal` — a plausible internal path with nothing
  behind it; the implied `ops` Linux account genuinely exists (visible in
  `/etc/passwd`) but has no valid credential or path to it at all.

## Fixed design constants (intentional, not secret-derived)
- `clerk`'s SSH password: `Cl3rk-Front2024!` (disclosed only via flag 4's XXE).
- PATH-hijack: `/opt/admin/bin` is world-writable and listed before
  `/usr/bin` in `/etc/cron.d/daily-report`'s own `PATH=`; root's cron runs
  `/opt/admin/daily_report.sh`, which calls `backup-helper` by bare name.
- Back Office's Flask app runs as the unprivileged `svc` account (not
  root) — the pickle RCE alone does NOT hand you root.
- Privesc: `chmod u+s` on the real `find` binary (resolved via
  `readlink -f`, not the `/usr/bin/find` symlink — matters on Debian).
  (An earlier draft tried SUID `awk`/`perl` first; Debian's `mawk` drops
  privileges inside its own `system()` builtin, and modern `perl` no
  longer supports setuid scripts at all without `suidperl`. `find -exec`
  is the one that's actually reliable here — verified, not assumed.)
- `docker-compose.yml`'s `internal-net` has `internal: true` — Back
  Office has no route to the internet either, not just no published ports.
