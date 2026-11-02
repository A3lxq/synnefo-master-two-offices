# Case File 4 (Master) — Two Offices

Part of **The Halcyon Protocol** CTF series. This box stands alone — you do
not need any other box in the series to play it.

> See [`STORY.md`](STORY.md) for the full case file.

## What this is

**Two linked hosts**, not one: **Front Desk** (published to your host) and
**Back Office** (internal-only — never published, reachable only by
pivoting through a shell on Front Desk). 10 flags, no decoys, split across
both hosts. The first two are easy; everything after requires chaining
techniques, and the last flag requires evidence from **both** hosts'
root accounts combined.

**This machine is intentionally vulnerable. Run it only on an isolated
network.**

## Requirements

- Docker + Docker Compose
- A player machine with: `curl`, a browser, an SSH client, basic XML
  crafting (for the XXE step), Python 3 (handy for scripting the pickle
  RCE payload in step 7)

## Starting the box

```
./start.sh
```
Generates a fresh `.env` with a random per-deployment secret and brings
both containers up.

- Front Desk: http://localhost:8004, SSH on `localhost:2204`
- Back Office: **not reachable from your host at all** — that's
  intentional, and part of the challenge.

## Flag format

`HLC{xxxxxxxxxx}` — submit exactly as found.

## Rules

- No decoy flags: everything matching the flag format is real and counts.
- Some things in this box are honeypots — red herrings that cost you time,
  not flags.
- Don't attack this box over a shared or public network.

## More

- [`STORY.md`](STORY.md) — the in-universe case file
- [`docs/hints.md`](docs/hints.md) — progressive hints
- [`docs/tools.md`](docs/tools.md) — what each tool is for
- [`docs/writeup/WRITEUP.md`](docs/writeup/WRITEUP.md) — full spoiler walkthrough
