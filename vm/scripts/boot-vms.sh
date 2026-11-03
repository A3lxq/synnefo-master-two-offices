#!/usr/bin/env bash
# boot-vms.sh — boots both VMs. Each has two NICs:
#   NIC0 (user/SLIRP, NAT): build/provisioning SSH access for both hosts,
#     plus the published web port on frontdesk only. Never forwards
#     backoffice's app port -- that one is reachable only via NIC1.
#   NIC1 (QEMU "socket" netdev): a direct point-to-point link between
#     the two guests, standing in for docker-compose's old
#     "internal-net" (internal: true) bridge -- no route out, no route
#     from the host, the two guests can only reach each other over it.
set -euo pipefail
cd "$(dirname "$0")/.."

ACCEL="tcg"
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
  ACCEL="kvm"
fi
echo "Using acceleration: $ACCEL"

LINK_PORT=20041

boot_one() {
  local NAME="$1" DISK="$2" SEED="$3" SSH_PORT="$4" WEB_FWD="$5" LINK_ARGS="$6" MAC1="$7"
  mkdir -p "$(dirname "$DISK")" "$(dirname "$0")/../$NAME/logs"
  qemu-system-x86_64 \
    -name "$NAME" \
    -machine type=q35,accel=$ACCEL \
    -cpu max -m 1536 -smp 2 \
    -drive file="$DISK",if=virtio,format=qcow2 \
    -drive file="$SEED",if=virtio,format=raw \
    -netdev user,id=net0,hostfwd=tcp:127.0.0.1:${SSH_PORT}-:22${WEB_FWD:+,$WEB_FWD} \
    -device virtio-net-pci,netdev=net0,mac=52:54:00:aa:00:0$([ "$NAME" = frontdesk ] && echo 1 || echo 2) \
    $LINK_ARGS \
    -device virtio-net-pci,netdev=net1,mac="$MAC1" \
    -display none \
    -serial file:"$NAME/logs/vm-console.log" \
    -monitor unix:"$NAME/disks/monitor.sock",server,nowait \
    -pidfile "$NAME/disks/vm.pid" \
    -daemonize
}

echo "== Starting frontdesk (internal-link listener) =="
boot_one frontdesk frontdesk/disks/frontdesk.qcow2 frontdesk/seed/seed.img 2204 \
  "hostfwd=tcp:127.0.0.1:8004-:5000" \
  "-netdev socket,id=net1,listen=127.0.0.1:${LINK_PORT}" \
  "52:54:00:aa:01:01"

sleep 1

echo "== Starting backoffice (internal-link connector) =="
boot_one backoffice backoffice/disks/backoffice.qcow2 backoffice/seed/seed.img 2205 \
  "" \
  "-netdev socket,id=net1,connect=127.0.0.1:${LINK_PORT}" \
  "52:54:00:aa:01:02"

echo "Both VMs starting."
echo "frontdesk:  ssh -i keys/ctfbuilder_ed25519 -p 2204 ctfbuilder@127.0.0.1   (web: http://127.0.0.1:8004)"
echo "backoffice: ssh -i keys/ctfbuilder_ed25519 -p 2205 ctfbuilder@127.0.0.1   (build-only -- app port never forwarded)"
echo "Stop with: ./scripts/stop-vms.sh"
