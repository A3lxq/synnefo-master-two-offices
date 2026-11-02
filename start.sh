#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [ ! -f .env ]; then
    echo "No .env found — generating one with a fresh CTF_SECRET."
    echo "CTF_SECRET=$(openssl rand -hex 32)" > .env
fi
docker compose up -d --build
echo
echo "Front Desk is up: http://localhost:8004  (ssh -p 2204 clerk@localhost once you have creds)"
echo "Back Office is internal-only — not reachable from the host."
