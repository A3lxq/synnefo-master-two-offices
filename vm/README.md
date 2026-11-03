# VM / OVA — Two Offices

**Two separate VM appliances**, not one: `frontdesk-two-offices-ctf.ova`
(published to your host) and `backoffice-two-offices-ctf.ova`
(never published — reachable only by pivoting through a shell on Front
Desk). Both are Ubuntu Server 24.04 LTS via QEMU/KVM + cloud-init
(NoCloud). Native build — real Flask apps managed by systemd, real
`cron`, real `openssh-server`. No Docker anywhere.

Each VM has **two network adapters**:
1. **NAT** — Front Desk's web app (port 5000) and both VMs' SSH are
   reachable through this one. Only Front Desk's web port matters to
   you as a player; the other SSH logins on this adapter are
   build/maintenance only and locked to a key you don't have.
2. **Internal link** — a private, isolated network between the two
   VMs only, replacing the original design's Docker-internal bridge
   network. Back Office has **no other route anywhere** — not to the
   internet, not to your host, only to Front Desk.

Flags are **static**, baked in once at provisioning time from a fixed
release secret — every copy of the exported OVAs has the same flags.
The release secret is never committed; `organizer/release-secret.txt`
(gitignored) holds it.

## Using the pre-built OVAs

Download **both** `.ova` files from this repo's Releases page, then:

1. Import `frontdesk-two-offices-ctf.ova` into VirtualBox (File >
   Import Appliance). On the settings screen, leave adapter 1 as
   **NAT**; adapter 2 will show as a network named
   `halcyon-master-internal` — after import, open
   Settings > Network > Adapter 2 and set it to **Internal Network**,
   with the network name `halcyon-master-internal` (type it exactly;
   it doesn't need to already exist, VirtualBox creates it).
2. Import `backoffice-two-offices-ctf.ova` the same way, and set
   **its** adapter 2 to Internal Network with the **same** name,
   `halcyon-master-internal`.
3. Power on **both** VMs (order doesn't matter) and wait about a
   minute for boot. Then browse to Front Desk's forwarded web port —
   check VirtualBox's Adapter 1 port-forwarding rules (or just open
   the VM's console and `curl localhost:5000`) to confirm the
   NAT-forwarded port, since VirtualBox's own default NAT port
   mapping varies by import.
4. Everything else happens inside the challenge — see `STORY.md` and
   `docs/hints.md` in the repo root.

VMware Workstation/Fusion: File > Open each `.ova`, then set each VM's
second network adapter to "LAN segment" (VMware's equivalent of
VirtualBox's Internal Network) with the same segment name on both VMs.

**This is an intentionally vulnerable pair of machines. Import them
only on an isolated network/host.**

## Build from source

```
cd vm
# put ubuntu-24.04-server-cloudimg-amd64.img in images/ first
# put your own ed25519 keypair in keys/ctfbuilder_ed25519[.pub],
# and reference the .pub in both hosts' cloud-init/user-data.yaml
# generate a release secret: openssl rand -hex 32 > ../organizer/release-secret.txt
./scripts/create-disks.sh
./scripts/boot-vms.sh        # wait a few minutes for first boot + cloud-init on both
RELEASE_SECRET=$(cat ../organizer/release-secret.txt)
scp -i keys/ctfbuilder_ed25519 -P 2204 scripts/remote-provision-frontdesk.sh ctfbuilder@127.0.0.1:/tmp/
scp -i keys/ctfbuilder_ed25519 -P 2205 scripts/remote-provision-backoffice.sh ctfbuilder@127.0.0.1:/tmp/
ssh -i keys/ctfbuilder_ed25519 -p 2205 ctfbuilder@127.0.0.1 "RELEASE_SECRET='$RELEASE_SECRET' bash /tmp/remote-provision-backoffice.sh"
ssh -i keys/ctfbuilder_ed25519 -p 2204 ctfbuilder@127.0.0.1 "RELEASE_SECRET='$RELEASE_SECRET' bash /tmp/remote-provision-frontdesk.sh"
./scripts/verify.sh           # proves all 10 flags before you export anything
./scripts/export-vms.sh
./scripts/export-ovas.sh
```

## Build note: the internal link

During build/test, the two VMs' internal NICs are connected directly
via a QEMU "socket" netdev pair (`frontdesk` listens, `backoffice`
connects) — a software crossover cable with no host route at all,
proving the exact topology the exported OVAs recreate via VirtualBox's
Internal Network / VMware's LAN segment feature. Both NICs are matched
by interface name (`enp0s2` for NAT, `enp0s3` for the internal link),
not MAC — see the single-host boxes' own `network-config.yaml` for why
that matters across hypervisors.
