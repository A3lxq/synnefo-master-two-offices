#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== Stopping both VMs =="
./scripts/stop-vms.sh

for HOST in frontdesk backoffice; do
  DISK="$HOST/disks/$HOST.qcow2"
  OUT_DIR="$HOST/dist"
  OUT_IMAGE="$OUT_DIR/$HOST-two-offices-ctf.qcow2"
  if [ ! -f "$DISK" ]; then echo "Missing $DISK. Build the VMs first." >&2; exit 1; fi
  echo "== [$HOST] Snapshotting this verified, ready-to-play state =="
  qemu-img snapshot -d clean-start "$DISK" 2>/dev/null || true
  qemu-img snapshot -c clean-start "$DISK"
  mkdir -p "$OUT_DIR"
  echo "== [$HOST] Flattening =="
  rm -f "$OUT_IMAGE"
  qemu-img convert -l clean-start -O qcow2 -c "$DISK" "$OUT_IMAGE"
  (cd "$OUT_DIR" && sha256sum "$(basename "$OUT_IMAGE")" > SHA256SUMS)
done

echo "== Restarting both VMs =="
./scripts/boot-vms.sh
echo "Done. Next: ./scripts/export-ovas.sh"
ls -lh frontdesk/dist backoffice/dist
