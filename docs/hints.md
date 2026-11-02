# Hints (progressive — try to only read as far as you need)

**Flag 1** — View page source on `/`.

**Flag 2** — A generic staff-login guess works here too.

**Flag 3** — `/import-schedule` accepts raw XML and parses it with DTDs
and external entities both enabled. A `<!DOCTYPE ... <!ENTITY xxe SYSTEM
"file:///some/path">` referenced as `&xxe;` inside the document gets
read server-side and reflected back.

**Flag 4** — The same trick works on more than one file. What other
file in that same secret folder might be worth reading?

**Flag 5** — Once you're in as `clerk`, look at what root's cron jobs
actually run, and the `PATH` they run with. If a writable directory
comes before the real system directories, and a script calls a command
by name instead of full path...

**Flag 6** — Once you're root (or even just clerk) on Front Desk, you're
inside this branch's own internal network. Something else lives on it,
reachable by hostname.

**Flag 7** — The Back Office API accepts a base64-encoded pickled
Python object and unpickles it. Python's `pickle` module will run
arbitrary code during unpickling if you control the bytes — look up
`__reduce__`.

**Flag 8** — The same RCE works more than once.

**Flag 9** — Check for SUID binaries once you have code execution
(`find / -perm -4000 -type f 2>/dev/null` — yes, really, check `find`
itself first).

**Flag 10** — You now have two short, non-flag-shaped strings from two
different root accounts. `final.enc` has been sitting on Front Desk's
homepage since before you started. `docker/flagcrypto.py` in this repo
tells you the exact scheme.
