# Phase 0: Build Environment

**Goal**: A dedicated QEMU virtual machine exists for building and testing ChaoticEvil. Your repo is accessible inside the VM with no file copying required. Snapshots protect against build environment corruption.

**Why not build on your main machine**: `lb build` runs as root, mounts filesystems, and modifies system-level binfmt handlers. A VM keeps all of that contained and reversible.

---

## Overview

Phase 0 is driven by two scripts that handle everything end-to-end:

| Script | When to run | What it does |
|---|---|---|
| `scripts/phase0-host.sh` | First | KVM check, QEMU install, nested virt, disk creation, ISO download + verify, SSH key generation, autoinstall seed ISO |
| `scripts/phase0-post-install.sh` | After host script | Fully unattended Ubuntu install, SSH config, repo mount, build deps, snapshots |

The only manual step is during the **host script**, which may ask for your `sudo` password.

---

## Step 0.1–0.5 — Host Setup

> **Shortcut**: all of Steps 0.1–0.5b are automated in `./scripts/phase0-host.sh`. Run it and skip to Step 0.6. The manual steps are documented below for reference.

---

### Step 0.1 — Check KVM is Available

KVM gives near-native performance. Verify it's enabled on your host:

```bash
# Check CPU supports virtualisation
egrep -c '(vmx|svm)' /proc/cpuinfo
# Any number > 0 means yes

# Check KVM module is loaded
lsmod | grep kvm
# Should show kvm_intel or kvm_amd

# Check you have access to /dev/kvm
ls -la /dev/kvm
# Should exist and be readable by your user (add yourself to kvm group if not)
sudo usermod -aG kvm $USER
```

---

### Step 0.2 — Install QEMU on the Host

Check what's already installed:
```bash
for pkg in qemu-system-x86 qemu-utils qemu-system-common ovmf; do
    dpkg -l "$pkg" 2>/dev/null | grep -q "^ii" \
        && echo "OK:      $pkg" \
        || echo "MISSING: $pkg"
done
```

Install any that are missing:
```bash
sudo apt install -y \
  qemu-system-x86 \
  qemu-utils \
  qemu-system-common \
  ovmf \
  xorriso
```

> `virtfs-proxy-helper` is included in `qemu-system-common`. 9p filesystem mounting uses the standard `mount` command — no extra package needed.

---

### Step 0.3 — Enable Nested Virtualisation

You'll run QEMU *inside* the VM to test ISOs. Nested KVM makes this fast.

```bash
# Auto-detect which KVM module is loaded
if lsmod | grep -q kvm_intel; then
    KVM_MOD="kvm_intel"; KVM_CONF="kvm-intel"
elif lsmod | grep -q kvm_amd; then
    KVM_MOD="kvm_amd"; KVM_CONF="kvm-amd"
else
    echo "No KVM module loaded — check Step 0.1"; exit 1
fi
echo "Using: $KVM_MOD"

# Check if nested is already enabled
cat /sys/module/${KVM_MOD}/parameters/nested
# Y or 1 = enabled, N or 0 = disabled

# If not enabled:
echo "options ${KVM_CONF} nested=1" | sudo tee /etc/modprobe.d/${KVM_CONF}.conf
sudo modprobe -r ${KVM_MOD} && sudo modprobe ${KVM_MOD}

# Verify — should now print Y or 1
cat /sys/module/${KVM_MOD}/parameters/nested
```

---

### Step 0.4 — Create the VM Disk

```bash
mkdir -p ~/vms
qemu-img create -f qcow2 ~/vms/chaoticevil-build.qcow2 100G
```

100 GB is thin-provisioned — it only uses actual disk space as the VM fills up.

---

### Step 0.5 — Download Ubuntu 24.04 Server ISO

Ubuntu 24.04 point releases change the filename (e.g. `24.04.2`, `24.04.4`). Find the current one first:

```bash
ISO_NAME=$(wget -qO- https://releases.ubuntu.com/24.04/ \
  | grep -o 'ubuntu-24\.04[^"]*-live-server-amd64\.iso' \
  | sort -V | tail -1)
echo "Downloading: $ISO_NAME"
wget -P ~/vms "https://releases.ubuntu.com/24.04/${ISO_NAME}"
```

Verify the download:
```bash
wget -O /tmp/ubuntu-checksums https://releases.ubuntu.com/24.04/SHA256SUMS

EXPECTED=$(grep "$ISO_NAME" /tmp/ubuntu-checksums | awk '{print $1}')
ACTUAL=$(sha256sum ~/vms/${ISO_NAME} | awk '{print $1}')

if [ "$EXPECTED" = "$ACTUAL" ]; then
    echo "OK: checksum verified"
else
    echo "MISMATCH — download may be corrupt"
    echo "  expected: $EXPECTED"
    echo "  actual:   $ACTUAL"
    exit 1
fi
```

Expected output on success:
```
OK: checksum verified
```

If you get a mismatch, delete the ISO and re-run the download.

---

### Step 0.5b — Generate SSH Key and Autoinstall Seed

Ubuntu's installer supports **autoinstall**: a YAML config on a small seed ISO that answers every installer screen automatically — no GTK window, no interaction needed.

```bash
SSH_KEY=~/.ssh/chaoticevil-build
ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "chaoticevil-build"
SSH_PUBKEY=$(cat "${SSH_KEY}.pub")

# Random password — VM is accessed via SSH key only, password is never used
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

# Create the seed ISO with label CIDATA (subiquity detects this automatically)
xorriso -as mkisofs \
  -output ~/vms/seed.iso \
  -volid "CIDATA" \
  -J -r \
  ~/vms/seed/user-data \
  ~/vms/seed/meta-data \
  2>/dev/null
```

> `xorriso` is already in the Step 0.2 package list.

---

## Step 0.6 — Install Ubuntu into the VM

> **Shortcut**: `phase0-post-install.sh` runs this automatically. The manual steps are documented here for reference.

With the seed ISO in place, the install is fully unattended. QEMU output goes to a log file; wait for the process to exit (the autoinstall config powers off the VM when done):

```bash
ISO_NAME=$(ls ~/vms/ubuntu-24.04*-live-server-amd64.iso | sort -V | tail -1 | xargs basename)

qemu-system-x86_64 \
  -m 8192 -smp 4 \
  -hda ~/vms/chaoticevil-build.qcow2 \
  -cdrom ~/vms/${ISO_NAME} \
  -drive file=~/vms/seed.iso,format=raw,if=virtio,media=cdrom \
  -boot d -enable-kvm \
  -net nic -net user \
  -nographic > ~/vms/autoinstall.log 2>&1 &

INSTALL_PID=$!
echo "Installing... (10–20 minutes)"
wait $INSTALL_PID || true
echo "Done — VM has powered off"
```

The autoinstall YAML (`~/vms/seed/user-data`) configures everything:
- Hostname: `chaoticevil-build`, user: `builder`
- SSH key from `~/.ssh/chaoticevil-build.pub` authorised — no password login needed
- Full disk LVM layout, OpenSSH server, passwordless sudo
- Powers off when done (so QEMU exits cleanly — no need to close a window)

### Manual fallback (if autoinstall doesn't work)

If the seed ISO isn't picked up, fall back to the interactive GTK installer:

```bash
qemu-system-x86_64 \
  -m 8192 -smp 4 \
  -hda ~/vms/chaoticevil-build.qcow2 \
  -cdrom ~/vms/${ISO_NAME} \
  -boot d -enable-kvm \
  -net nic -net user,hostfwd=tcp::2222-:22 \
  -display gtk
```

### Installer screens (manual path only)

| Screen | What to do |
|---|---|
| **Language** | English (or your preference) |
| **Keyboard layout** | Match your host keyboard |
| **Installation type** | Choose **Ubuntu Server (minimised)** |
| **Network** | Leave as-is — should show `10.0.2.15/24`. Hit Done. |
| **Proxy** | Leave blank |
| **Ubuntu archive mirror** | Leave as default — wait for the green tick |
| **Storage** | Choose **Use an entire disk**, leave LVM on |
| **Storage confirmation** | Done → Continue |
| **Profile** | Hostname: `chaoticevil-build`, username: `builder`, choose a password |
| **SSH** | Tick **Install OpenSSH server** |
| **Ubuntu Pro** | Skip for now |
| **Snaps** | Don't select anything — Done |

The install takes 5–10 minutes. When **Reboot Now** appears, press Enter then **immediately close the QEMU GTK window** — don't wait for it to boot back into the installer.

> If you didn't close in time and ended up at a GRUB prompt or installer screen: close the window anyway and proceed to the next step.

---

## Steps 0.7–0.12 — Post-Install Setup

> **Shortcut**: all of Steps 0.7–0.12 are automated in `./scripts/phase0-post-install.sh`. The manual steps are documented below for reference.

---

### Step 0.7 — Boot the Installed VM

This uses `-nographic` (unlike Step 0.6) — the VM is a headless server with no display. QEMU backgrounds immediately and you interact with it entirely over SSH.

```bash
qemu-system-x86_64 \
  -m 8192 \
  -smp 4 \
  -hda ~/vms/chaoticevil-build.qcow2 \
  -boot c \
  -enable-kvm \
  -net nic \
  -net user,hostfwd=tcp::2222-:22 \
  -virtfs local,path=/home/thzero/own,mount_tag=distro-repo,security_model=mapped \
  -nographic &
```

The VM takes ~20–30 seconds to boot. SSH in:

```bash
ssh -p 2222 builder@localhost
```

Expected output on successful login:
```
Welcome to Ubuntu 24.04 LTS (GNU/Linux ...)
builder@chaoticevil-build:~$
```

If you get `Connection refused`, the VM is still booting — wait a few seconds and retry.

Add to `~/.ssh/config` on your host for convenience:
```
Host chaoticevil-build
    HostName localhost
    Port 2222
    User builder
```

Then just `ssh chaoticevil-build`.

> To stop the VM: inside the VM run `sudo poweroff`, or kill the backgrounded QEMU process with `kill %1`.

---

### Step 0.8 — Mount the Repo Inside the VM

The `-virtfs` flag shares `/home/thzero/own` from your host into the VM as a 9p filesystem. Mount it inside the VM:

```bash
# Inside the VM:
sudo mkdir -p /mnt/distro-repo
sudo mount -t 9p -o trans=virtio distro-repo /mnt/distro-repo

# Add to /etc/fstab so it mounts automatically on boot
echo "distro-repo  /mnt/distro-repo  9p  trans=virtio,_netdev  0  0" | \
  sudo tee -a /etc/fstab
```

Now `/mnt/distro-repo` inside the VM is your live repo from the host. **ISOs written to `output/` appear directly at `/home/thzero/own/output/` on the host — no copying needed.**

---

### Step 0.9 — Snapshot: Clean Ubuntu Install

Before installing any build dependencies, take a snapshot so you can roll back to a clean Ubuntu install if anything goes wrong.

```bash
# Shut down the VM cleanly first
# (Inside the VM): sudo poweroff
# Then on the host:

qemu-img snapshot -c "clean-ubuntu-install" ~/vms/chaoticevil-build.qcow2

# Verify
qemu-img snapshot -l ~/vms/chaoticevil-build.qcow2
```

---

### Step 0.10 — Install Build Dependencies Inside the VM

```bash
# Inside the VM:
sudo apt update
sudo apt install -y \
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
```

---

### Step 0.11 — Snapshot: Build Dependencies Installed

```bash
# Shut down the VM cleanly, then on the host:
qemu-img snapshot -c "build-deps-installed" ~/vms/chaoticevil-build.qcow2

qemu-img snapshot -l ~/vms/chaoticevil-build.qcow2
# Should show both snapshots
```

Revert to this snapshot any time a build corrupts the environment:
```bash
qemu-img snapshot -a "build-deps-installed" ~/vms/chaoticevil-build.qcow2
```

---

### Step 0.12 — Convenience Start Script

Create `~/vms/start-build-vm.sh` on your host:

```bash
cat > ~/vms/start-build-vm.sh <<'EOF'
#!/bin/bash
qemu-system-x86_64 \
  -m 8192 -smp 4 \
  -hda ~/vms/chaoticevil-build.qcow2 \
  -boot c -enable-kvm \
  -net nic -net user,hostfwd=tcp::2222-:22 \
  -virtfs local,path=/home/thzero/own,mount_tag=distro-repo,security_model=mapped \
  -nographic &
echo "VM started (PID $!). SSH in with: ssh chaoticevil-build"
EOF
chmod +x ~/vms/start-build-vm.sh
```

Start the VM: `~/vms/start-build-vm.sh`
SSH in: `ssh chaoticevil-build`

---

## Day-to-day VM usage

```bash
# Start the VM
~/vms/start-build-vm.sh

# SSH in
ssh chaoticevil-build

# Stop the VM (from inside)
sudo poweroff
```

To revert to a known-good state:
```bash
# Revert to build-deps-installed (most recent clean baseline)
qemu-img snapshot -a "build-deps-installed" ~/vms/chaoticevil-build.qcow2
```

---

## Snapshot Strategy

| Snapshot name | When taken |
|---|---|
| `clean-ubuntu-install` | After repo mount, before build deps |
| `build-deps-installed` | After build deps installed |
| `phase1-complete` | After Phase 1 checklist passes |
| `phase2-complete` | After Phase 2 checklist passes |
| _(and so on)_ | After each phase checklist passes |

---

## Checklist

- [ ] `./scripts/phase0-host.sh` completed successfully
- [ ] Ubuntu installed into VM (Step 0.6)
- [ ] `./scripts/phase0-post-install.sh` completed successfully
- [ ] `ssh chaoticevil-build` works
- [ ] `/mnt/distro-repo` inside VM shows repo contents
- [ ] `clean-ubuntu-install` and `build-deps-installed` snapshots exist
- [ ] `~/vms/start-build-vm.sh` created

---

## Next Step

→ [Phase 1: Foundation](phases/PHASE1_FOUNDATION.md)
