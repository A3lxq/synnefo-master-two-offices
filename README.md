# Case File 4 (Master) — Two Offices

![banner](banner.jpeg)

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

## Running it

This box ships as **two** VM appliances — download both `.ova` files
from this repo's [Releases](../../releases) page and import both into
VirtualBox (File > Import Appliance) or VMware Workstation/Fusion
(File > Open). Each VM needs its second network adapter set to the
same Internal Network / LAN segment name so the two can reach each
other. See [`vm/README.md`](vm/README.md) for exact steps and for
rebuilding from source.

There is no Docker build in this repo (an earlier one was removed; a
Docker version may be added back separately).

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
- [`flags/generate_flags.py`](flags/generate_flags.py) — the per-deployment flag derivation scheme, used by `organizer/verify.py`
