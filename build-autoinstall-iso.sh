#!/usr/bin/env bash
set -euo pipefail

# =============================
# Config (override via env vars)
# =============================
# Ubuntu ISO URL (change if you want a different point release)
ISO_URL="${ISO_URL:-https://releases.ubuntu.com/24.04/ubuntu-24.04.1-live-server-amd64.iso}"
ISO_DIR="${ISO_DIR:-/var/lib/vz/template/iso}"
OUT_ISO="${OUT_ISO:-$ISO_DIR/ubuntu-24.04-autoinstall.iso}"
WORKDIR="${WORKDIR:-/root/ubuntu24-autoinstall}"
HOSTNAME="${HOSTNAME:-ubuntu-vm}"
ADMIN_USER="${ADMIN_USER:-admin}"
PLAINTEXT_PASS="${PLAINTEXT_PASS:-0okm)OKM#13}"

# =============================
# Helpers
# =============================
log() { printf "\n\033[1;32m[+] %s\033[0m\n" "$*"; }
warn() { printf "\n\033[1;33m[!] %s\033[0m\n" "$*"; }
die() { printf "\n\033[1;31m[ERROR] %s\033[0m\n" "$*"; exit 1; }

cleanup() {
  set +e
  mountpoint -q "$WORKDIR/mnt" && umount "$WORKDIR/mnt"
}
trap cleanup EXIT

# =============================
# Pre-reqs
# =============================
log "Installing dependencies (xorriso, rsync, curl, genisoimage if available)..."
apt-get update -y >/dev/null
apt-get install -y xorriso rsync curl genisoimage >/dev/null

# =============================
# Get original ISO
# =============================
mkdir -p "$ISO_DIR" "$WORKDIR/mnt" "$WORKDIR/iso"
ORIG_ISO="$ISO_DIR/$(basename "$ISO_URL")"

if [ ! -s "$ORIG_ISO" ]; then
  log "Downloading Ubuntu ISO → $ORIG_ISO"
  curl -L --fail -o "$ORIG_ISO" "$ISO_URL" || die "Failed to download ISO from $ISO_URL"
else
  log "Using existing ISO at $ORIG_ISO"
fi

# =============================
# Copy ISO contents to workdir
# =============================
log "Mounting original ISO and copying contents..."
mount -o loop "$ORIG_ISO" "$WORKDIR/mnt"
rsync -aH --delete "$WORKDIR/mnt"/ "$WORKDIR/iso"/
umount "$WORKDIR/mnt"

# =============================
# Write cloud-init seed files
# =============================
log "Writing NoCloud seed (user-data, meta-data)..."
mkdir -p "$WORKDIR/iso/nocloud"

# Your autoinstall + post-install config
cat > "$WORKDIR/iso/nocloud/user-data" <<USERDATA
#cloud-config
autoinstall:
  version: 1
  locale: en_US.UTF-8
  keyboard: { layout: us }
  interactive-sections: []     # skip ALL prompts
  identity:
    hostname: ${HOSTNAME}
    username: ${ADMIN_USER}
    # a hash is required by autoinstall identity; we will overwrite with chpasswd below
    password: "\$6\$exDY1mhS4KUYCE/2\$zmn9ToZwTKLhCw.b4/b9sxwOry2H2Gcv0UZZcQEeU9vpo/7dD3vcWpTqferf8Ohh4RORpL2cih8lS6GfO5i4K0"
    realname: Admin User

  network:
    version: 2
    ethernets:
      all-en:
        match: { name: "en*" }
        dhcp4: true
        dhcp6: false
        optional: true

  storage:
    layout: { name: zfs }    # change to { name: direct } if you don't want ZFS

  packages:
    - openssh-server
    - zfsutils-linux
    - vim
    - htop

  ssh:
    install-server: true
    allow-pw: true

  # Post-install cloud-init (runs inside target)
  user-data:
    disable_root: false
    ssh_pwauth: true
    users:
      - name: ${ADMIN_USER}
        sudo: ALL=(ALL) NOPASSWD:ALL
        shell: /bin/bash
        lock_passwd: false
    chpasswd:
      list: |
        root:${PLAINTEXT_PASS}
        ${ADMIN_USER}:${PLAINTEXT_PASS}
      expire: false
    write_files:
      - path: /root/setup-client-datasets.sh
        permissions: '0755'
        content: |
          #!/bin/bash
          set -e
          sleep 10
          DATASET="\$(zfs list -H -o name / | awk '/ROOT/ {print \$1; exit}')"
          if [ -n "\$DATASET" ]; then
            zfs create -o mountpoint=/var/log/audit "\$DATASET/var-log-audit" 2>/dev/null || true
            zfs create -o mountpoint=/var/log/tmp -o exec=off -o devices=off "\$DATASET/var-log-tmp" 2>/dev/null || true
            zfs create -o mountpoint=/var/virtual "\$DATASET/var-virtual" 2>/dev/null || true
            zfs set exec=off devices=off setuid=off "\$DATASET/var/log" 2>/dev/null || true
            mkdir -p /var/virtual /var/log/audit /var/log/tmp
            chmod 1777 /tmp
            zfs mount -a
          fi
          rm -f /root/setup-client-datasets.sh
    runcmd:
      - [ /root/setup-client-datasets.sh ]

  late-commands:
    - curtin in-target --target=/target -- systemctl enable systemd-networkd.service
    - curtin in-target --target=/target -- systemctl enable systemd-resolved.service
    - curtin in-target --target=/target -- ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
    - curtin in-target --target=/target -- systemctl enable ssh.service
    - curtin in-target --target=/target -- sed -ri 's/^[# ]*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config

  shutdown: reboot
USERDATA

cat > "$WORKDIR/iso/nocloud/meta-data" <<METADATA
instance-id: ${HOSTNAME}-001
local-hostname: ${HOSTNAME}
METADATA

# =============================
# Add autoinstall flags to all boot entries
# =============================
log "Patching GRUB configs to add autoinstall flags..."
# Add flags before the trailing ' ---' in any kernel line that boots casper/vmlinuz
grep -Rl "casper/vmlinuz" "$WORKDIR/iso" | grep -E '\.cfg$' | xargs -r \
  sed -ri 's#( *linux[[:space:]]+/casper/vmlinuz.*) ---#\1 autoinstall ds=nocloud;s=/cdrom/nocloud/ ---#'

# Verify
if ! grep -RInq "autoinstall ds=nocloud" "$WORKDIR/iso"; then
  die "Failed to patch GRUB kernel lines with autoinstall flags."
fi

# =============================
# Build the final ISO
# =============================
log "Building final autoinstall ISO..."
# Detect correct UEFI image path inside the ISO tree
EFI_IMG=""
for p in "$WORKDIR/iso/boot/grub/efi.img" \
         "$WORKDIR/iso/EFI/BOOT/BOOTx64.EFI" \
         "$WORKDIR/iso/EFI/boot/grubx64.efi"; do
  if [ -f "$p" ]; then
    EFI_IMG="${p#$WORKDIR/iso/}"
    break
  fi
done
[ -z "$EFI_IMG" ] && die "Could not find a UEFI boot image inside $WORKDIR/iso (looked in EFI/ and boot/grub/)"

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

log "Done! Final ISO → $OUT_ISO"
log "Attach ONLY this ISO to your VM and boot. Install is 100% unattended."
warn "Note: Plaintext password used for autoinstall (root + ${ADMIN_USER}). Change via ENV var PLAINTEXT_PASS if needed."
