#!/usr/bin/env bash
set -euo pipefail

### ========= CONFIGURABLE =========
ISO_URL="${ISO_URL:-https://releases.ubuntu.com/24.04/ubuntu-24.04.1-live-server-amd64.iso}"
ISO_STORAGE="${ISO_STORAGE:-local}"             # Proxmox storage ID where ISOs live (usually 'local')
VM_STORAGE="${VM_STORAGE:-local-lvm}"          # Proxmox storage for VM disk
ISO_DIR="${ISO_DIR:-/var/lib/vz/template/iso}" # path that maps to $ISO_STORAGE:iso
WORKDIR="${WORKDIR:-/root/ubuntu24-autoinstall}"
OUT_ISO_NAME="${OUT_ISO_NAME:-ubuntu-24.04-autoinstall.iso}"
HOSTNAME_CFG="${HOSTNAME_CFG:-ubuntu-vm}"
ADMIN_USER="${ADMIN_USER:-admin}"
PLAINTEXT_PASS="${PLAINTEXT_PASS:-Admin@123}"

# Proxmox VM settings (change as needed)
VMID="${VMID:-100}"
VM_NAME="${VM_NAME:-ub24-auto}"
MEMORY_MB="${MEMORY_MB:-4096}"
CORES="${CORES:-2}"
DISK_SIZE="${DISK_SIZE:-32G}"
BRIDGE="${BRIDGE:-vmbr0}"
### =================================

log() { printf "\n\033[1;32m[+] %s\033[0m\n" "$*"; }
warn() { printf "\n\033[1;33m[!] %s\033[0m\n" "$*"; }
die() { printf "\n\033[1;31m[ERROR] %s\033[0m\n" "$*"; exit 1; }

cleanup() {
  set +e
  mountpoint -q "$WORKDIR/mnt" && umount "$WORKDIR/mnt"
}
trap cleanup EXIT

# Install deps
log "Installing dependencies..."
apt-get update -y >/dev/null
apt-get install -y xorriso rsync curl genisoimage >/dev/null

# Prepare dirs
mkdir -p "$ISO_DIR" "$WORKDIR/mnt" "$WORKDIR/iso"

# Download ISO if missing
ORIG_ISO="$ISO_DIR/$(basename "$ISO_URL")"
if [ ! -s "$ORIG_ISO" ]; then
  log "Downloading Ubuntu ISO → $ORIG_ISO"
  curl -L --fail -o "$ORIG_ISO" "$ISO_URL" || die "Failed to download $ISO_URL"
else
  log "Using existing ISO at $ORIG_ISO"
fi

# Copy ISO contents
log "Mounting and copying ISO contents..."
mount -o loop "$ORIG_ISO" "$WORKDIR/mnt"
rsync -aH --delete "$WORKDIR/mnt"/ "$WORKDIR/iso"/
umount "$WORKDIR/mnt"

# Create NoCloud seed files
log "Writing NoCloud seed (user-data, meta-data)..."
mkdir -p "$WORKDIR/iso/nocloud"

USERDATA_FILE="$WORKDIR/iso/nocloud/user-data"
: > "$USERDATA_FILE"
printf '%s\n' '#cloud-config' >> "$USERDATA_FILE"
printf '%s\n' 'autoinstall:' >> "$USERDATA_FILE"
printf '%s\n' '  version: 1' >> "$USERDATA_FILE"
printf '%s\n' '  locale: en_US.UTF-8' >> "$USERDATA_FILE"
printf '%s\n' '  keyboard: { layout: us }' >> "$USERDATA_FILE"
printf '%s\n' '  interactive-sections: []' >> "$USERDATA_FILE"
printf '%s\n' '  identity:' >> "$USERDATA_FILE"
printf '%s\n' "    hostname: ${HOSTNAME_CFG}" >> "$USERDATA_FILE"
printf '%s\n' "    username: ${ADMIN_USER}" >> "$USERDATA_FILE"
printf '%s\n' '    password: "$6$exDY1mhS4KUYCE/2$zmn9ToZwTKLhCw.b4/b9sxwOry2H2Gcv0UZZcQEeU9vpo/7dD3vcWpTqferf8Ohh4RORpL2cih8lS6GfO5i4K0"' >> "$USERDATA_FILE"
printf '%s\n' '    realname: Admin User' >> "$USERDATA_FILE"
printf '%s\n' '' >> "$USERDATA_FILE"
printf '%s\n' '  network:' >> "$USERDATA_FILE"
printf '%s\n' '    version: 2' >> "$USERDATA_FILE"
printf '%s\n' '    ethernets:' >> "$USERDATA_FILE"
printf '%s\n' '      all-en:' >> "$USERDATA_FILE"
printf '%s\n' '        match: { name: "en*" }' >> "$USERDATA_FILE"
printf '%s\n' '        dhcp4: true' >> "$USERDATA_FILE"
printf '%s\n' '        dhcp6: false' >> "$USERDATA_FILE"
printf '%s\n' '        optional: true' >> "$USERDATA_FILE"
printf '%s\n' '' >> "$USERDATA_FILE"
printf '%s\n' '  storage:' >> "$USERDATA_FILE"
printf '%s\n' '    layout: { name: zfs }' >> "$USERDATA_FILE"
printf '%s\n' '' >> "$USERDATA_FILE"
printf '%s\n' '  packages:' >> "$USERDATA_FILE"
printf '%s\n' '    - openssh-server' >> "$USERDATA_FILE"
printf '%s\n' '    - zfsutils-linux' >> "$USERDATA_FILE"
printf '%s\n' '    - vim' >> "$USERDATA_FILE"
printf '%s\n' '    - htop' >> "$USERDATA_FILE"
printf '%s\n' '' >> "$USERDATA_FILE"
printf '%s\n' '  ssh:' >> "$USERDATA_FILE"
printf '%s\n' '    install-server: true' >> "$USERDATA_FILE"
printf '%s\n' '    allow-pw: true' >> "$USERDATA_FILE"
printf '%s\n' '' >> "$USERDATA_FILE"
printf '%s\n' '  user-data:' >> "$USERDATA_FILE"
printf '%s\n' '    disable_root: false' >> "$USERDATA_FILE"
printf '%s\n' '    ssh_pwauth: true' >> "$USERDATA_FILE"
printf '%s\n' '    users:' >> "$USERDATA_FILE"
printf '%s\n' "      - name: ${ADMIN_USER}" >> "$USERDATA_FILE"
printf '%s\n' '        sudo: ALL=(ALL) NOPASSWD:ALL' >> "$USERDATA_FILE"
printf '%s\n' '        shell: /bin/bash' >> "$USERDATA_FILE"
printf '%s\n' '        lock_passwd: false' >> "$USERDATA_FILE"
printf '%s\n' '    chpasswd:' >> "$USERDATA_FILE"
printf '%s\n' '      list: |' >> "$USERDATA_FILE"
printf '%s\n' "        root:${PLAINTEXT_PASS}" >> "$USERDATA_FILE"
printf '%s\n' "        ${ADMIN_USER}:${PLAINTEXT_PASS}" >> "$USERDATA_FILE"
printf '%s\n' '      expire: false' >> "$USERDATA_FILE"
printf '%s\n' '    write_files:' >> "$USERDATA_FILE"
printf '%s\n' "      - path: /root/setup-client-datasets.sh" >> "$USERDATA_FILE"
printf '%s\n' "        permissions: '0755'" >> "$USERDATA_FILE"
printf '%s\n' '        content: |' >> "$USERDATA_FILE"
printf '%s\n' '          #!/bin/bash' >> "$USERDATA_FILE"
printf '%s\n' '          set -e' >> "$USERDATA_FILE"
printf '%s\n' '          sleep 10' >> "$USERDATA_FILE"
printf '%s\n' '          DATASET="$(zfs list -H -o name / | awk '\''/ROOT/ {print $1; exit}'\'')" >> "$USERDATA_FILE"
printf '%s\n' '          if [ -n "$DATASET" ]; then' >> "$USERDATA_FILE"
printf '%s\n' '            zfs create -o mountpoint=/var/log/audit "$DATASET/var-log-audit" 2>/dev/null || true' >> "$USERDATA_FILE"
printf '%s\n' '            zfs create -o mountpoint=/var/log/tmp -o exec=off -o devices=off "$DATASET/var-log-tmp" 2>/dev/null || true' >> "$USERDATA_FILE"
printf '%s\n' '            zfs create -o mountpoint=/var/virtual "$DATASET/var-virtual" 2>/dev/null || true' >> "$USERDATA_FILE"
printf '%s\n' '            zfs set exec=off devices=off setuid=off "$DATASET/var/log" 2>/dev/null || true' >> "$USERDATA_FILE"
printf '%s\n' '            mkdir -p /var/virtual /var/log/audit /var/log/tmp' >> "$USERDATA_FILE"
printf '%s\n' '            chmod 1777 /tmp' >> "$USERDATA_FILE"
printf '%s\n' '            zfs mount -a' >> "$USERDATA_FILE"
printf '%s\n' '          fi' >> "$USERDATA_FILE"
printf '%s\n' '          rm -f /root/setup-client-datasets.sh' >> "$USERDATA_FILE"
printf '%s\n' '    runcmd:' >> "$USERDATA_FILE"
printf '%s\n' '      - [ /root/setup-client-datasets.sh ]' >> "$USERDATA_FILE"
printf '%s\n' '' >> "$USERDATA_FILE"
printf '%s\n' '  late-commands:' >> "$USERDATA_FILE"
printf '%s\n' '    - curtin in-target --target=/target -- systemctl enable systemd-networkd.service' >> "$USERDATA_FILE"
printf '%s\n' '    - curtin in-target --target=/target -- systemctl enable systemd-resolved.service' >> "$USERDATA_FILE"
printf '%s\n' '    - curtin in-target --target=/target -- ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf' >> "$USERDATA_FILE"
printf '%s\n' '    - curtin in-target --target=/target -- systemctl enable ssh.service' >> "$USERDATA_FILE"
printf '%s\n' "    - curtin in-target --target=/target -- sed -ri 's/^[# ]*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config" >> "$USERDATA_FILE"
printf '%s\n' '' >> "$USERDATA_FILE"
printf '%s\n' '  shutdown: reboot' >> "$USERDATA_FILE"

METADATA_FILE="$WORKDIR/iso/nocloud/meta-data"
: > "$METADATA_FILE"
printf '%s\n' "instance-id: ${HOSTNAME_CFG}-001" >> "$METADATA_FILE"
printf '%s\n' "local-hostname: ${HOSTNAME_CFG}" >> "$METADATA_FILE"

# Patch boot entries (add autoinstall flags)
log "Patching GRUB kernel lines..."
CFG_LIST="$(grep -Rl "casper/vmlinuz" "$WORKDIR/iso" | grep -E '\.cfg$' || true)"
if [ -n "$CFG_LIST" ]; then
  # shellcheck disable=SC2086
  sed -ri 's#( *linux[[:space:]]+/casper/vmlinuz.*) ---#\1 autoinstall ds=nocloud;s=/cdrom/nocloud/ ---#' $CFG_LIST
fi
grep -RIn "autoinstall ds=nocloud" "$WORKDIR/iso" >/dev/null || die "Failed to patch GRUB configs"

# Build final ISO
log "Building autoinstall ISO..."
EFI_IMG=""
for p in "$WORKDIR/iso/boot/grub/efi.img" "$WORKDIR/iso/EFI/BOOT/BOOTx64.EFI" "$WORKDIR/iso/EFI/boot/grubx64.efi"; do
  if [ -f "$p" ]; then EFI_IMG="${p#$WORKDIR/iso/}"; break; fi
done
[ -z "$EFI_IMG" ] && die "Could not find a UEFI boot image in ISO tree"

OUT_ISO="$ISO_DIR/$OUT_ISO_NAME"
xorriso -as mkisofs \
  -r -V UBUNTU_24_04_AUTOINSTALL \
  -o "$OUT_ISO" \
  -J -l -iso-level 3 \
  -partition_offset 16 \
  -b boot/grub/i386-pc/eltorito.img \
     -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot \
  -e "$EFI_IMG" \
     -no-emul-boot \
  -isohybrid-gpt-basdat \
  "$WORKDIR/iso"

log "ISO ready: $OUT_ISO"

# Proxmox VM creation
log "Creating Proxmox VM $VMID ($VM_NAME)..."
if qm status "$VMID" >/dev/null 2>&1; then
  die "VMID $VMID already exists. Set a different VMID."
fi

qm create "$VMID" --name "$VM_NAME" --memory "$MEMORY_MB" --cores "$CORES" --sockets 1 --ostype l26
qm set "$VMID" --scsihw virtio-scsi-pci --scsi0 "${VM_STORAGE}:0,format=qcow2,size=${DISK_SIZE}"
qm set "$VMID" --net0 virtio,bridge="${BRIDGE}"
qm set "$VMID" --ide2 "${ISO_STORAGE}:iso/$(basename "$OUT_ISO")",media=cdrom
qm set "$VMID" --boot order=ide2,scsi0
qm set "$VMID" --serial0 socket --vga serial0
qm set "$VMID" --agent enabled=1 || true

log "Starting VM $VMID ..."
qm start "$VMID"

log "All set! VM is booting from the unattended ISO and will auto-install Ubuntu."
warn "Credentials after install → user: ${ADMIN_USER} / root, password: ${PLAINTEXT_PASS}"
