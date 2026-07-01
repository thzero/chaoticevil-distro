#!/bin/bash
# Phase 0 post-install — run on your HOST after phase0-host.sh completes.
#
# Steps performed automatically:
#   0.6  — Ubuntu autoinstall (unattended, ~10-20 min)
#   0.7  — Boot installed VM
#   SSH  — Configure ~/.ssh/config
#   0.8  — Mount 9p repo share inside VM
#   0.9  — Snapshot: clean-ubuntu-install
#   0.10 — Install build dependencies
#   0.11 — Snapshot: build-deps-installed
#   0.12 — Create ~/vms/start-build-vm.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
VM_DISK=~/vms/chaoticevil-build.qcow2
SEED_ISO=~/vms/seed.iso
SSH_KEY=~/.ssh/chaoticevil-build
SSH_USER="builder"
SSH_OPTS="-p 2222 -i $SSH_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}OK${NC}:    $*"; }
fail() { echo -e "${RED}ERROR${NC}: $*" >&2; exit 1; }
info() { echo -e "${YELLOW}-->${NC}   $*"; }

# ── Prerequisites ─────────────────────────────────────────────────────────────
[ -f "$VM_DISK" ]  || fail "VM disk not found: $VM_DISK — run phase0-host.sh first"
[ -f "$SEED_ISO" ] || fail "Seed ISO not found: $SEED_ISO — run phase0-host.sh first"
[ -f "$SSH_KEY" ]  || fail "SSH key not found: $SSH_KEY — run phase0-host.sh first"

ISO_NAME=$(ls ~/vms/ubuntu-24.04*-live-server-amd64.iso 2>/dev/null \
  | sort -V | tail -1 | xargs -I{} basename {} 2>/dev/null || true)
[ -n "$ISO_NAME" ] || fail "Ubuntu ISO not found in ~/vms/ — run phase0-host.sh first"

# ── Helpers ───────────────────────────────────────────────────────────────────
start_vm() {
    info "Starting VM..."
    qemu-system-x86_64 \
      -m 8192 -smp 4 \
      -hda "$VM_DISK" \
      -boot c -enable-kvm \
      -net nic -net user,hostfwd=tcp::2222-:22 \
      -virtfs local,path="$REPO_DIR",mount_tag=distro-repo,security_model=mapped \
      -nographic > ~/vms/qemu.log 2>&1 &
    QEMU_PID=$!
    echo "      VM PID: $QEMU_PID (log: ~/vms/qemu.log)"
}

wait_for_ssh() {
    info "Waiting for SSH (up to 150s)..."
    for i in $(seq 1 30); do
        if ssh $SSH_OPTS -o BatchMode=yes -o ConnectTimeout=3 \
               "${SSH_USER}@localhost" true 2>/dev/null; then
            ok "SSH is up"
            return 0
        fi
        printf "      attempt %d/30\r" "$i"
        sleep 5
    done
    fail "SSH did not come up — check ~/vms/qemu.log for errors"
}

stop_vm() {
    info "Shutting down VM cleanly..."
    ssh $SSH_OPTS "${SSH_USER}@localhost" 'sudo poweroff' 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
    ok "VM stopped"
}

# ── Step 0.6: Unattended Ubuntu install ───────────────────────────────────────
echo "=== Step 0.6: Ubuntu Autoinstall ==="
info "Booting installer with autoinstall seed (10–20 minutes, no interaction needed)..."
info "ISO: $ISO_NAME"
info "Log: ~/vms/autoinstall.log"

qemu-system-x86_64 \
  -m 8192 -smp 4 \
  -hda "$VM_DISK" \
  -cdrom ~/vms/"$ISO_NAME" \
  -drive file="$SEED_ISO",format=raw,if=virtio,media=cdrom \
  -boot d -enable-kvm \
  -net nic -net user \
  -nographic > ~/vms/autoinstall.log 2>&1 &
INSTALL_PID=$!

echo -n "      Installing"
while kill -0 "$INSTALL_PID" 2>/dev/null; do
    echo -n "."
    sleep 10
done
echo ""
wait "$INSTALL_PID" || true   # autoinstall poweroffs — QEMU exit code may be non-zero
ok "Installation complete"

# ── SSH config ────────────────────────────────────────────────────────────────
echo ""
echo "=== SSH Config ==="
if ! grep -q "Host chaoticevil-build" ~/.ssh/config 2>/dev/null; then
    mkdir -p ~/.ssh && chmod 700 ~/.ssh
    cat >> ~/.ssh/config <<EOF

Host chaoticevil-build
    HostName localhost
    Port 2222
    User ${SSH_USER}
    IdentityFile ${SSH_KEY}
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF
    ok "~/.ssh/config entry added"
else
    ok "~/.ssh/config entry already present"
fi

# ── Step 0.7: Boot installed VM ───────────────────────────────────────────────
echo ""
echo "=== Step 0.7: First Boot ==="
start_vm
wait_for_ssh

# ── Step 0.8: Mount repo share ────────────────────────────────────────────────
echo ""
echo "=== Step 0.8: Mounting repo share ==="
ssh $SSH_OPTS "${SSH_USER}@localhost" 'bash -s mount' < "$SCRIPT_DIR/phase0-vm.sh"

# ── Step 0.9: Snapshot — clean-ubuntu-install ─────────────────────────────────
echo ""
echo "=== Step 0.9: Snapshot — clean-ubuntu-install ==="
stop_vm
qemu-img snapshot -c "clean-ubuntu-install" "$VM_DISK"
ok "Snapshot 'clean-ubuntu-install' taken"

# ── Step 0.10: Build dependencies ─────────────────────────────────────────────
echo ""
echo "=== Step 0.10: Installing build dependencies ==="
start_vm
wait_for_ssh
ssh $SSH_OPTS "${SSH_USER}@localhost" 'bash -s deps' < "$SCRIPT_DIR/phase0-vm.sh"

# ── Step 0.11: Snapshot — build-deps-installed ────────────────────────────────
echo ""
echo "=== Step 0.11: Snapshot — build-deps-installed ==="
stop_vm
qemu-img snapshot -c "build-deps-installed" "$VM_DISK"
ok "Snapshot 'build-deps-installed' taken"

echo ""
qemu-img snapshot -l "$VM_DISK"

# ── Step 0.12: Start script ───────────────────────────────────────────────────
echo ""
echo "=== Step 0.12: Creating start script ==="
cat > ~/vms/start-build-vm.sh <<SCRIPT
#!/bin/bash
qemu-system-x86_64 \\
  -m 8192 -smp 4 \\
  -hda ~/vms/chaoticevil-build.qcow2 \\
  -boot c -enable-kvm \\
  -net nic -net user,hostfwd=tcp::2222-:22 \\
  -virtfs local,path="${REPO_DIR}",mount_tag=distro-repo,security_model=mapped \\
  -nographic > ~/vms/qemu.log 2>&1 &
echo "VM started (PID \$!). SSH in with: ssh chaoticevil-build"
SCRIPT
chmod +x ~/vms/start-build-vm.sh
ok "~/vms/start-build-vm.sh created"

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo "========================================================"
echo "Phase 0 complete!"
echo ""
echo "Start the VM:  ~/vms/start-build-vm.sh"
echo "SSH in:        ssh chaoticevil-build"
echo "Repo inside:   /mnt/distro-repo"
echo ""
echo "Next: follow phases/PHASE1_FOUNDATION.md"
echo "========================================================"
