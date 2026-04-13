#!/bin/bash
# Phase 0 VM-side setup — runs INSIDE the build VM.
# Invoked automatically by phase0-post-install.sh via SSH.
# Can also be run manually: ssh chaoticevil-build 'bash -s' [mount|deps] < scripts/phase0-vm.sh
#
# Stages:
#   mount  — mounts the 9p repo share and adds /etc/fstab entry
#   deps   — installs build dependencies
#   (none) — runs both stages in order
set -euo pipefail

STAGE="${1:-all}"

GREEN='\033[0;32m'; NC='\033[0m'
ok()   { echo -e "${GREEN}OK${NC}:  $*"; }
info() { echo "-->  $*"; }

run_mount() {
    echo "=== Step 0.8: Mounting repo share ==="

    sudo mkdir -p /mnt/distro-repo

    if mountpoint -q /mnt/distro-repo; then
        ok "/mnt/distro-repo already mounted"
    else
        sudo mount -t 9p -o trans=virtio distro-repo /mnt/distro-repo
        ok "/mnt/distro-repo mounted"
    fi

    if grep -q 'distro-repo' /etc/fstab; then
        ok "fstab entry already present"
    else
        echo "distro-repo  /mnt/distro-repo  9p  trans=virtio,_netdev  0  0" | \
            sudo tee -a /etc/fstab > /dev/null
        ok "fstab entry added — share will auto-mount on boot"
    fi

    info "Repo contents:"
    ls /mnt/distro-repo
}

run_deps() {
    echo "=== Step 0.10: Installing build dependencies ==="

    sudo apt-get update -q
    sudo apt-get install -y \
      live-build \
      qemu-user-static \
      binfmt-support \
      debootstrap \
      squashfs-tools \
      xorriso \
      isolinux \
      syslinux-efi \
      grub-efi-amd64-bin \
      grub-efi-arm64-bin \
      grub-pc-bin \
      git \
      make \
      curl \
      rsync

    ok "Build dependencies installed"
}

case "$STAGE" in
    mount) run_mount ;;
    deps)  run_deps ;;
    all)   run_mount; echo ""; run_deps ;;
    *) echo "Usage: $0 [mount|deps]" >&2; exit 1 ;;
esac
