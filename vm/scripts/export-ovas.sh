#!/usr/bin/env bash
# export-ovas.sh — builds the two OVF/OVA appliances (run export-vms.sh
# first). Each VM gets TWO network adapters in its OVF: "NAT" (the
# published/build network) and "halcyon-master-internal" (the private
# link between the two VMs, replacing docker-compose's old
# "internal-net"). VirtualBox's own Import Appliance wizard lets you
# map each adapter to a real attachment type on import -- see
# vm/README.md for the exact steps (Internal Network, same name on
# both VMs).
set -euo pipefail
cd "$(dirname "$0")/.."

MEM_MB=1024
CPUS=2

build_one() {
  local HOST="$1" VM_NAME="$2" TITLE="$3" ANNOTATION="$4"
  local SRC_QCOW2="$HOST/dist/$HOST-two-offices-ctf.qcow2"
  local OUT_DIR="$HOST/dist"
  local VMDK="$OUT_DIR/$VM_NAME-disk001.vmdk"
  local OVF="$OUT_DIR/$VM_NAME.ovf"
  local MF="$OUT_DIR/$VM_NAME.mf"
  local OVA="$OUT_DIR/$VM_NAME.ova"

  if [ ! -f "$SRC_QCOW2" ]; then
    echo "Missing $SRC_QCOW2. Run ./scripts/export-vms.sh first." >&2
    exit 1
  fi

  echo "== [$HOST] Converting qcow2 -> stream-optimized VMDK =="
  rm -f "$VMDK"
  qemu-img convert -p -O vmdk -o subformat=streamOptimized "$SRC_QCOW2" "$VMDK"

  local VMDK_SIZE CAPACITY_BYTES
  VMDK_SIZE=$(stat -c %s "$VMDK")
  CAPACITY_BYTES=$(qemu-img info --output=json "$SRC_QCOW2" | python3 -c 'import json,sys; print(json.load(sys.stdin)["virtual-size"])')

  echo "== [$HOST] Writing OVF descriptor (2 network adapters) =="
  cat > "$OVF" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<Envelope vmw:buildId="build-$VM_NAME" xmlns="http://schemas.dmtf.org/ovf/envelope/1" xmlns:cim="http://schemas.dmtf.org/wbem/wscim/1/common" xmlns:ovf="http://schemas.dmtf.org/ovf/envelope/1" xmlns:rasd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_ResourceAllocationSettingData" xmlns:vmw="http://www.vmware.com/schema/ovf" xmlns:vssd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_VirtualSystemSettingData" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <References>
    <File ovf:href="$(basename "$VMDK")" ovf:id="file1" ovf:size="$VMDK_SIZE"/>
  </References>
  <DiskSection>
    <Info>Virtual disk information</Info>
    <Disk ovf:capacity="$CAPACITY_BYTES" ovf:capacityAllocationUnits="byte" ovf:diskId="vmdisk1" ovf:fileRef="file1" ovf:format="http://www.vmware.com/interfaces/specifications/vmdk.html#streamOptimized" ovf:populatedSize="$VMDK_SIZE"/>
  </DiskSection>
  <NetworkSection>
    <Info>The list of logical networks</Info>
    <Network ovf:name="NAT">
      <Description>Host-only / NAT network for the isolated CTF lab. Do not bridge this to a public network.</Description>
    </Network>
    <Network ovf:name="halcyon-master-internal">
      <Description>Private link to the other Two Offices VM. Map BOTH VMs' second adapter to VirtualBox's "Internal Network" attachment type, with this exact same network name on both, so they can reach only each other.</Description>
    </Network>
  </NetworkSection>
  <VirtualSystem ovf:id="$VM_NAME">
    <Info>$TITLE</Info>
    <Name>$VM_NAME</Name>
    <OperatingSystemSection ovf:id="101" ovf:version="24.04" vmw:osType="ubuntu64Guest">
      <Info>The kind of installed guest operating system</Info>
      <Description>Ubuntu Linux (64-bit)</Description>
    </OperatingSystemSection>
    <VirtualHardwareSection>
      <Info>Virtual hardware requirements</Info>
      <System>
        <vssd:ElementName>Virtual Hardware Family</vssd:ElementName>
        <vssd:InstanceID>0</vssd:InstanceID>
        <vssd:VirtualSystemIdentifier>$VM_NAME</vssd:VirtualSystemIdentifier>
        <vssd:VirtualSystemType>vmx-19</vssd:VirtualSystemType>
      </System>
      <Item>
        <rasd:AllocationUnits>hertz * 10^6</rasd:AllocationUnits>
        <rasd:Description>Number of virtual CPUs</rasd:Description>
        <rasd:ElementName>$CPUS virtual CPU(s)</rasd:ElementName>
        <rasd:InstanceID>1</rasd:InstanceID>
        <rasd:ResourceType>3</rasd:ResourceType>
        <rasd:VirtualQuantity>$CPUS</rasd:VirtualQuantity>
      </Item>
      <Item>
        <rasd:AllocationUnits>byte * 2^20</rasd:AllocationUnits>
        <rasd:Description>Memory Size</rasd:Description>
        <rasd:ElementName>${MEM_MB}MB of memory</rasd:ElementName>
        <rasd:InstanceID>2</rasd:InstanceID>
        <rasd:ResourceType>4</rasd:ResourceType>
        <rasd:VirtualQuantity>$MEM_MB</rasd:VirtualQuantity>
      </Item>
      <Item>
        <rasd:Address>0</rasd:Address>
        <rasd:Description>IDE Controller</rasd:Description>
        <rasd:ElementName>IDE Controller 0</rasd:ElementName>
        <rasd:InstanceID>3</rasd:InstanceID>
        <rasd:ResourceSubType>PIIX4</rasd:ResourceSubType>
        <rasd:ResourceType>5</rasd:ResourceType>
      </Item>
      <Item>
        <rasd:AddressOnParent>0</rasd:AddressOnParent>
        <rasd:ElementName>Hard Disk 1</rasd:ElementName>
        <rasd:HostResource>ovf:/disk/vmdisk1</rasd:HostResource>
        <rasd:InstanceID>4</rasd:InstanceID>
        <rasd:Parent>3</rasd:Parent>
        <rasd:ResourceType>17</rasd:ResourceType>
      </Item>
      <Item>
        <rasd:AddressOnParent>7</rasd:AddressOnParent>
        <rasd:AutomaticAllocation>true</rasd:AutomaticAllocation>
        <rasd:Connection>NAT</rasd:Connection>
        <rasd:Description>E1000 ethernet adapter -- NAT / build network</rasd:Description>
        <rasd:ElementName>Network adapter 1</rasd:ElementName>
        <rasd:InstanceID>5</rasd:InstanceID>
        <rasd:ResourceSubType>E1000</rasd:ResourceSubType>
        <rasd:ResourceType>10</rasd:ResourceType>
      </Item>
      <Item>
        <rasd:AddressOnParent>8</rasd:AddressOnParent>
        <rasd:AutomaticAllocation>true</rasd:AutomaticAllocation>
        <rasd:Connection>halcyon-master-internal</rasd:Connection>
        <rasd:Description>E1000 ethernet adapter -- private link to the other VM (set to Internal Network on import)</rasd:Description>
        <rasd:ElementName>Network adapter 2</rasd:ElementName>
        <rasd:InstanceID>6</rasd:InstanceID>
        <rasd:ResourceSubType>E1000</rasd:ResourceSubType>
        <rasd:ResourceType>10</rasd:ResourceType>
      </Item>
    </VirtualHardwareSection>
    <AnnotationSection>
      <Info>A description of the meaning of the VM</Info>
      <Annotation>$ANNOTATION</Annotation>
    </AnnotationSection>
  </VirtualSystem>
</Envelope>
EOF

  echo "== [$HOST] Validating the OVF XML is well-formed =="
  python3 -c "import xml.etree.ElementTree as ET; ET.parse('$OVF')" && echo "XML OK"

  echo "== [$HOST] Writing the manifest (.mf) =="
  local OVF_HASH VMDK_HASH
  OVF_HASH=$(sha256sum "$OVF" | cut -d' ' -f1)
  VMDK_HASH=$(sha256sum "$VMDK" | cut -d' ' -f1)
  cat > "$MF" <<EOF
SHA256($(basename "$OVF"))= $OVF_HASH
SHA256($(basename "$VMDK"))= $VMDK_HASH
EOF

  echo "== [$HOST] Packing the .ova =="
  rm -f "$OVA"
  tar -C "$OUT_DIR" -cf "$OVA" "$(basename "$OVF")" "$(basename "$MF")" "$(basename "$VMDK")"

  echo "== [$HOST] Structural self-check =="
  tar -tvf "$OVA"
  ( cd "$OUT_DIR" && sha256sum -c "$(basename "$MF")" )

  echo
  echo "Built: $OVA ($(du -h "$OVA" | cut -f1))"
  rm -f "$VMDK" "$OVF" "$MF"
}

build_one frontdesk frontdesk-two-offices-ctf \
  "Case File 4 (Master) -- Two Offices -- Front Desk -- Halcyon Protocol CTF VM (Ubuntu Server 24.04 LTS, native)" \
  "Case File 4 (Master) -- Two Offices -- Front Desk. Deliberately vulnerable, isolated lab use only. Import together with the matching Back Office VM and set both VMs' second network adapter to Internal Network with the same name (see vm/README.md)."

build_one backoffice backoffice-two-offices-ctf \
  "Case File 4 (Master) -- Two Offices -- Back Office -- Halcyon Protocol CTF VM (Ubuntu Server 24.04 LTS, native)" \
  "Case File 4 (Master) -- Two Offices -- Back Office. Deliberately vulnerable, isolated lab use only. Never reachable except via the Front Desk VM's internal link -- import together with Front Desk and set both VMs' second network adapter to Internal Network with the same name (see vm/README.md)."

echo
echo "Both OVAs built. VBoxManage not found on this host -- only structurally"
echo "validated (XML, tar layout, manifest checksums). Test a real import with"
echo "VBoxManage import <ova> --dry-run or VMware Workstation/Fusion's File > Open."
