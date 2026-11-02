# Tools you'll use in this box

| Tool | What it's for here |
|---|---|
| curl / browser | Recon, triggering requests, the XXE payload. |
| Hand-crafted XML (`<!DOCTYPE ... <!ENTITY ...>`) | The XXE injection (flags 3, 4). Burp Repeater makes iterating on this easier. |
| `ssh` | Log into Front Desk as `clerk` once you have real credentials. |
| Manual enumeration (`cat /etc/cron.d/*`, `ls -la` on script directories) | Spot the PATH-hijack privesc (flag 5) — no automated tool needed, just reading configuration carefully. |
| `curl` from inside the clerk SSH session | The actual pivot: reaching `backoffice:6000` directly, since your own machine never can. |
| Python 3's `pickle` + `base64` | Build the deserialization RCE payload (flags 7, 8) — see the writeup for exact code. |
| GTFOBins (gtfobins.github.io) | Confirm `find`'s `-exec` privilege-escalation technique once you spot its SUID bit (flag 9). |
| `docker/flagcrypto.py` (ships with this repo) | Decrypt `final.enc` once you have both fragments (flag 10). |
