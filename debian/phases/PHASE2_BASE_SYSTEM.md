# Phase 2: Base System (Debian)

**Goal**: All three editions build to bootable Debian-based ISOs with correct package sets and ARM64 verified.

**Prerequisite**: [Phase 1 (Debian)](PHASE1_FOUNDATION.md) complete — `make server ARCH=amd64` produces a working ISO.

**Differences from [ubuntu/phases/PHASE2_BASE_SYSTEM.md](../../ubuntu/phases/PHASE2_BASE_SYSTEM.md)**:
- Ubuntu-specific packages removed from all lists
- `unattended-upgrades` hook uses Debian origin strings
- Mainline kernel hook targets `linux-image-${PKG_ARCH}` not `linux-image-generic`
- Desktop uses PipeWire instead of PulseAudio
- No `calamares-settings-ubuntu` or `calamares-data` (Phase 4 handles Calamares fully)

---

## Step 2.1 — Common Base Packages

`common/package-lists/base.list.chroot`:

```
# Networking
openssh-server
curl
wget
ca-certificates
apt-transport-https
gnupg

# System
sudo
bash-completion
unattended-upgrades
apt-utils
lsb-release
locales
tzdata

# Security
ufw
fail2ban
```

> Do **not** add `friendly-recovery`, `update-manager-core`, or `command-not-found` — these are Ubuntu-only packages that do not exist on Debian.

### Unattended upgrades hook (Debian origin strings)

Create `common/hooks/base/01-unattended-upgrades.hook.chroot`:

```bash
#!/bin/bash
set -e

cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "Debian:${distro_codename}-security";
    "Debian:${distro_codename}";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF

cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
```

```bash
chmod +x common/hooks/base/01-unattended-upgrades.hook.chroot
```

> **Ubuntu version** used `"${distro_id}:${distro_codename}-security"` — Debian uses `"Debian:..."` without the distro_id prefix.

### Mainline kernel hook (Debian removal target)

Copy `common/hooks/base/02-mainline-kernel.hook.chroot` from the Ubuntu plan and replace the `apt-get remove` block:

```bash
# Was (Ubuntu):
apt-get remove -y --purge \
    linux-image-generic linux-headers-generic \
    linux-image-generic-hwe-24.04 linux-headers-generic-hwe-24.04 \
    2>/dev/null || true

# Now (Debian) — arch-specific meta package name:
apt-get remove -y --purge \
    linux-image-${PKG_ARCH} linux-headers-${PKG_ARCH} \
    2>/dev/null || true
```

All other parts of the hook (wget from kernel.ubuntu.com, dpkg -i, apt-mark hold) are identical.

---

## Step 2.2 — Server Edition

`editions/server/package-lists/server.list.chroot` — identical to the Ubuntu plan:

```
fail2ban
htop
iotop
tmux
vim
nano
ncdu
net-tools
nmap
rsync
lsof
strace
dnsutils
traceroute
jq
```

Server hardening hook — identical to the Ubuntu plan. See [ubuntu/phases/PHASE2_BASE_SYSTEM.md § Step 2.2](../../ubuntu/phases/PHASE2_BASE_SYSTEM.md).

---

## Step 2.3 — Desktop Edition

`editions/desktop/package-lists/desktop.list.chroot`:

```
# Desktop environment
xfce4
xfce4-goodies
xfce4-terminal
xfce4-screensaver
thunar
thunar-volman
thunar-archive-plugin

# Display manager
lightdm
lightdm-gtk-greeter
lightdm-gtk-greeter-settings

# Network
network-manager
network-manager-gnome
nm-tray

# Audio — PipeWire (default in Debian trixie, replaces PulseAudio)
pipewire
pipewire-pulse
wireplumber
pavucontrol

# Printing
cups
system-config-printer

# Bluetooth
blueman
bluez

# Fonts
fonts-noto
fonts-noto-cjk
fonts-liberation

# Accessibility
at-spi2-core

# File handling
gvfs
gvfs-backends
file-roller

# System tools
gnome-disk-utility
gparted
baobab

# Flatpak
flatpak
xdg-desktop-portal
xdg-desktop-portal-gtk
xdg-user-dirs
xdg-user-dirs-gtk

# Plymouth
plymouth
plymouth-themes

# Calamares — base package only; configured manually in Phase 4
calamares
```

**Audio note**: Debian trixie ships PipeWire as the default audio system. Use `pipewire`, `pipewire-pulse` (PulseAudio compatibility layer), and `wireplumber` (session manager). Do not add `pulseaudio` — it conflicts.

**Calamares note**: Just `calamares` — no `calamares-settings-ubuntu`, `calamares-data`, or Ubuntu helper packages. All Calamares configuration is written manually in Phase 4.

### Desktop setup hook

`editions/desktop/hooks/01-desktop-setup.hook.chroot` — identical to the Ubuntu plan. See [ubuntu/phases/PHASE2_BASE_SYSTEM.md § Step 2.3](../../ubuntu/phases/PHASE2_BASE_SYSTEM.md).

---

## Step 2.4 — Developer Edition

`editions/developer/package-lists/developer.list.chroot` — everything from the Desktop list above, plus:

```
# Version control
git
git-lfs
gh

# Build tools
build-essential
cmake
make
pkg-config
autoconf
automake
libtool
ninja-build

# Languages
python3
python3-pip
python3-venv
python3-dev
nodejs
npm
golang
rustc
cargo
default-jdk

# Containers
docker.io
docker-compose-plugin
buildah
skopeo

# Utilities
vim
htop
tmux
jq
ripgrep
fd-find
bat
fzf
zsh
```

**Debian package differences from the Ubuntu developer list**:

| Ubuntu | Debian | Note |
|---|---|---|
| `openjdk-21-jdk` | `default-jdk` | Installs current default JDK (21 in trixie) |
| `golang-go` | `golang` | Different package name |
| `nodejs` | `nodejs` | Same, but trixie ships a newer version |

### Developer setup hook

`editions/developer/hooks/01-developer-setup.hook.chroot` — identical to the Ubuntu plan (Docker group, zsh default shell, etc.).

---

## Step 2.5 — Custom APT Repository

Identical to the Ubuntu plan. See [ubuntu/phases/PHASE2_BASE_SYSTEM.md § Step 2.5](../../ubuntu/phases/PHASE2_BASE_SYSTEM.md).

The `Codename` field in your Release file should match `DEBIAN_CODENAME` (`trixie`).

---

## Step 2.6 — Build and Verify (amd64)

```bash
make server ARCH=amd64
make desktop ARCH=amd64
make developer ARCH=amd64
```

### Debian-specific checks

```bash
# Verify no Ubuntu packages leaked in
dpkg -l | grep ubuntu     # Must return nothing
dpkg -l | grep -i focal   # Must return nothing
dpkg -l | grep -i noble   # Must return nothing

# Verify Debian base
cat /etc/os-release | grep ID_LIKE   # ID_LIKE=debian
lsb_release -a                       # Distributor ID: ChaoticEvil

# Verify PipeWire (not PulseAudio) on Desktop/Developer
systemctl --user status pipewire     # active
pactl info | grep "Server Name"      # Should show PipeWire

# Verify mainline kernel
uname -r   # Should show 7.1.x or current mainline version
```

Standard checks (XFCE loads, Flatpak present, etc.) are identical to the Ubuntu plan.

---

## Step 2.7 — ARM64

```bash
make server ARCH=arm64
make desktop ARCH=arm64
make developer ARCH=arm64
```

Testing procedure identical to the Ubuntu plan. See [ubuntu/phases/PHASE2_BASE_SYSTEM.md § Step 2.7](../../ubuntu/phases/PHASE2_BASE_SYSTEM.md).

---

## Step 2.8 — Commit

```bash
git add .
git commit -m "feat(debian): package lists and hooks for all three editions"
git push origin dev
```

---

## Checklist

- [ ] `base.list.chroot` — no Ubuntu-specific packages (`friendly-recovery`, `update-manager-core`, etc.)
- [ ] `01-unattended-upgrades.hook.chroot` — uses `"Debian:${distro_codename}-security"` origins
- [ ] `02-mainline-kernel.hook.chroot` — removes `linux-image-${PKG_ARCH}` not `linux-image-generic`
- [ ] Desktop list uses PipeWire (`pipewire`, `pipewire-pulse`, `wireplumber`) — no `pulseaudio`
- [ ] Desktop list has `calamares` only (no `calamares-settings-ubuntu`)
- [ ] Developer list uses `default-jdk` and `golang` (not `openjdk-21-jdk`, `golang-go`)
- [ ] `dpkg -l | grep ubuntu` returns nothing in built ISO
- [ ] `os-release` shows `ID_LIKE=debian`
- [ ] PipeWire active on Desktop/Developer editions
- [ ] Mainline kernel version confirmed: `uname -r`
- [ ] ARM64 server boots in QEMU
- [ ] Changes committed to `dev`
