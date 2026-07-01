#!/bin/bash
# Phase 0 host setup — run on your HOST before installing Ubuntu into the VM.
# Covers: KVM check, QEMU install, nested virtualisation, VM disk creation,
# Ubuntu ISO download and checksum verification, SSH key generation,
# and autoinstall seed ISO creation.
#
# After this script completes, run:
#   ./scripts/phase0-post-install.sh
# That script boots the VM, runs the unattended Ubuntu installer automatically,
# then sets up the repo share, installs build deps, and takes snapshots.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../distro.conf"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}OK${NC}:    $*"; }
fail() { echo -e "${RED}ERROR${NC}: $*" >&2; exit 1; }
info() { echo -e "${YELLOW}-->${NC}   $*"; }

echo "=== Phase 0: Host Setup ==="
echo ""

# ── Step 0.1: KVM ────────────────────────────────────────────────────────────
info "Step 0.1: Checking KVM..."

count=$(grep -cE '(vmx|svm)' /proc/cpuinfo || true)
[ "$count" -gt 0 ] \
  || fail "CPU does not support virtualisation (vmx/svm not found in /proc/cpuinfo)"
ok "CPU supports virtualisation ($count hardware threads)"

[ -e /dev/kvm ] \
  || fail "/dev/kvm not found — KVM module not loaded or not enabled in BIOS"
ok "/dev/kvm exists"

if ! groups | grep -qw kvm; then
    info "Adding $USER to kvm group..."
    sudo usermod -aG kvm "$USER"
    echo "      NOTE: log out and back in for group change to take effect"
fi

# ── Step 0.2: QEMU packages ──────────────────────────────────────────────────
echo ""
info "Step 0.2: Checking QEMU packages..."
MISSING=()
for pkg in qemu-system-x86 qemu-utils qemu-system-common ovmf xorriso; do
    dpkg -l "$pkg" 2>/dev/null | grep -q "^ii" || MISSING+=("$pkg")
done

if [ ${#MISSING[@]} -gt 0 ]; then
    info "Installing: ${MISSING[*]}"
    sudo apt-get install -y "${MISSING[@]}"
fi
ok "QEMU packages installed"

# ── Step 0.3: Nested virtualisation ─────────────────────────────────────────
echo ""
info "Step 0.3: Checking nested virtualisation..."
if lsmod | grep -q kvm_intel; then
    KVM_MOD="kvm_intel"; KVM_CONF="kvm-intel"
elif lsmod | grep -q kvm_amd; then
    KVM_MOD="kvm_amd"; KVM_CONF="kvm-amd"
else
    fail "No KVM module loaded — check Step 0.1"
fi

NESTED=$(cat /sys/module/${KVM_MOD}/parameters/nested 2>/dev/null || echo "0")
if [[ "$NESTED" == "Y" || "$NESTED" == "1" ]]; then
    ok "Nested virtualisation already enabled ($KVM_MOD)"
else
    info "Enabling nested virtualisation for $KVM_MOD..."
    echo "options ${KVM_CONF} nested=1" | sudo tee /etc/modprobe.d/${KVM_CONF}.conf > /dev/null
    sudo modprobe -r "${KVM_MOD}" && sudo modprobe "${KVM_MOD}"
    NESTED=$(cat /sys/module/${KVM_MOD}/parameters/nested)
    [[ "$NESTED" == "Y" || "$NESTED" == "1" ]] \
      || fail "Failed to enable nested virtualisation — reboot may be required"
    ok "Nested virtualisation enabled"
fi

# ── Step 0.4: VM disk ────────────────────────────────────────────────────────
echo ""
info "Step 0.4: Creating VM disk..."
mkdir -p ~/vms
if [ -f ~/vms/chaoticevil-build.qcow2 ]; then
    ok "~/vms/chaoticevil-build.qcow2 already exists"
else
    qemu-img create -f qcow2 ~/vms/chaoticevil-build.qcow2 100G
    ok "VM disk created (100G thin-provisioned)"
fi

# ── Step 0.5: Download + verify ISO ─────────────────────────────────────────
echo ""
info "Step 0.5: Finding current Ubuntu 24.04 ISO..."
ISO_NAME=$(wget -qO- https://releases.ubuntu.com/24.04/ \
  | grep -o 'ubuntu-24\.04[^"]*-live-server-amd64\.iso' \
  | sort -V | tail -1)
[ -n "$ISO_NAME" ] || fail "Could not determine ISO filename from releases.ubuntu.com"
info "Current ISO: $ISO_NAME"

if [ -f ~/vms/"$ISO_NAME" ]; then
    info "ISO already present, verifying checksum..."
else
    info "Downloading $ISO_NAME..."
    wget -P ~/vms "https://releases.ubuntu.com/24.04/${ISO_NAME}"
fi

wget -qO /tmp/ubuntu-checksums https://releases.ubuntu.com/24.04/SHA256SUMS
EXPECTED=$(grep "$ISO_NAME" /tmp/ubuntu-checksums | awk '{print $1}')
ACTUAL=$(sha256sum ~/vms/"${ISO_NAME}" | awk '{print $1}')

if [ "$EXPECTED" = "$ACTUAL" ]; then
    ok "ISO checksum verified"
else
    rm -f ~/vms/"$ISO_NAME"
    fail "Checksum mismatch — corrupt download deleted. Re-run this script."
fi

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""

# ── Step 0.5b: SSH key + autoinstall seed ────────────────────────────────────
info "Step 0.5b: Generating SSH key and autoinstall seed ISO..."

SSH_KEY=~/.ssh/chaoticevil-build
if [ ! -f "$SSH_KEY" ]; then
    ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "chaoticevil-build"
    ok "SSH key generated: $SSH_KEY"
else
    ok "SSH key already exists: $SSH_KEY"
fi
SSH_PUBKEY=$(cat "${SSH_KEY}.pub")

# Random password — VM is only accessed via SSH key, password is never used
PASS_HASH=$(openssl passwd -6 "$(openssl rand -base64 16)")

mkdir -p ~/vms/seed
cat > ~/vms/seed/user-data <<EOF
#cloud-config
autoinstall:
  version: 1
  locale: en_US.UTF-8
  keyboard:
    layout: us
  identity:
    hostname: chaoticevil-build
    username: builder
    password: "${PASS_HASH}"
  ssh:
    install-server: true
    authorized-keys:
      - "${SSH_PUBKEY}"
  storage:
    layout:
      name: lvm
  updates: security
  ubuntu-pro:
    token: ''
  late-commands:
    - echo 'builder ALL=(ALL) NOPASSWD:ALL' > /target/etc/sudoers.d/builder
    - chmod 440 /target/etc/sudoers.d/builder
  shutdown: poweroff
EOF
touch ~/vms/seed/meta-data

xorriso -as mkisofs \
  -output ~/vms/seed.iso \
  -volid "CIDATA" \
  -J -r \
  ~/vms/seed/user-data \
  ~/vms/seed/meta-data \
  2>/dev/null

ok "Autoinstall seed ISO created: ~/vms/seed.iso"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "========================================================"
echo "Host setup complete."
echo ""
echo "NEXT — run the post-install script."
echo "It will boot the VM, run the unattended Ubuntu installer"
echo "(10-20 min, no interaction needed), then set up the repo"
echo "share, build deps, and snapshots automatically."
echo ""
echo "  ./scripts/phase0-post-install.sh"
echo "========================================================"
