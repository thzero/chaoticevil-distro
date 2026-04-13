# Phase 2: Base System

**Goal**: All three editions build to bootable ISOs with correct package sets, Ubuntu repos, and ARM64 support verified.

**Prerequisite**: [Phase 1: Foundation](PHASE1_FOUNDATION.md) complete — `make server ARCH=amd64` produces a working ISO.

---

## Step 2.1 — Finalize Common Base Packages

Edit `common/package-lists/base.list`. These packages go into **every** edition.

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

### Configure unattended upgrades hook

Create `common/hooks/base/01-unattended-upgrades.hook.chroot`:
```bash
#!/bin/bash
set -e
# Enable security updates only by default
cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF

# Enable automatic updates
cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
```

Make it executable:
```bash
chmod +x common/hooks/base/01-unattended-upgrades.hook.chroot
```

> **All hooks in `hooks/` must be executable** or live-build silently skips them.

---

## Step 2.2 — Server Edition Packages

Edit `editions/server/package-lists/server.list`:
```
# Server tools
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

# Web/service stack (optional — remove if not needed)
# nginx
# certbot
```

### Server: disable GUI-related services hook

Create `editions/server/hooks/01-server-hardening.hook.chroot`:
```bash
#!/bin/bash
set -e

# Ensure no desktop services are installed
# Disable unnecessary services
systemctl disable ModemManager 2>/dev/null || true
systemctl disable avahi-daemon 2>/dev/null || true
systemctl disable cups 2>/dev/null || true

# Enable firewall by default, deny incoming
ufw --force enable
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh

# Harden SSH
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/X11Forwarding yes/X11Forwarding no/' /etc/ssh/sshd_config
```

```bash
chmod +x editions/server/hooks/01-server-hardening.hook.chroot
```

---

## Step 2.3 — Desktop Edition Packages

Edit `editions/desktop/package-lists/desktop.list`:
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

# Audio
pulseaudio
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

# Plymouth (boot splash)
plymouth
plymouth-themes

# Calamares installer
calamares
calamares-data
```

### Desktop: configure Flatpak and portal hook

Create `editions/desktop/hooks/01-desktop-setup.hook.chroot`:
```bash
#!/bin/bash
set -e

# Set XDG portal backend for XFCE
mkdir -p /usr/share/xdg-desktop-portal
cat > /usr/share/xdg-desktop-portal/xfce-portals.conf << 'EOF'
[preferred]
default=gtk
EOF

# Enable Flatpak system-wide
flatpak remote-add --system --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true

# Allow users in the flatpak group to manage Flatpaks without sudo
usermod -a -G flatpak root 2>/dev/null || true
```

```bash
chmod +x editions/desktop/hooks/01-desktop-setup.hook.chroot
```

---

## Step 2.4 — Developer Edition Packages

Edit `editions/developer/package-lists/developer.list`:
```
# Everything from desktop (live-build doesn't support includes between lists,
# so we duplicate the desktop list here and add dev packages below)

# Desktop environment
xfce4
xfce4-goodies
xfce4-terminal
xfce4-screensaver
thunar
thunar-volman
thunar-archive-plugin
lightdm
lightdm-gtk-greeter
lightdm-gtk-greeter-settings
network-manager
network-manager-gnome
nm-tray
pulseaudio
pavucontrol
cups
blueman
bluez
fonts-noto
fonts-noto-cjk
fonts-liberation
at-spi2-core
gvfs
gvfs-backends
file-roller
gnome-disk-utility
gparted
baobab
flatpak
xdg-desktop-portal
xdg-desktop-portal-gtk
xdg-user-dirs
xdg-user-dirs-gtk
plymouth
plymouth-themes
calamares
calamares-data

# Developer tools — version control
git
git-lfs
gh

# Developer tools — build
build-essential
cmake
make
pkg-config
autoconf
automake
libtool
ninja-build

# Developer tools — languages
python3
python3-pip
python3-venv
python3-dev
nodejs
npm
golang-go
rustc
cargo
openjdk-21-jdk

# Developer tools — containers
docker.io
docker-compose-plugin
buildah
skopeo

# Developer tools — utilities
jq
httpie
sqlite3
postgresql-client
mysql-client
redis-tools
vim
neovim
tmux
zsh
fzf
ripgrep
bat
fd-find
tree
ncdu

# Developer tools — network
wireshark
nmap
net-tools
dnsutils

# Flatpak
flatpak
xdg-desktop-portal
xdg-desktop-portal-gtk
xdg-user-dirs
xdg-user-dirs-gtk
```

### Developer: additional setup hook

Create `editions/developer/hooks/01-developer-setup.hook.chroot`:
```bash
#!/bin/bash
set -e

# Add current user to docker group (Calamares will handle the actual user)
# Add docker group so it exists for new users
groupadd -f docker

# Enable Docker service
systemctl enable docker

# Set XDG portal for XFCE (same as desktop)
mkdir -p /usr/share/xdg-desktop-portal
cat > /usr/share/xdg-desktop-portal/xfce-portals.conf << 'EOF'
[preferred]
default=gtk
EOF

# Install nvm for Node version management
# Do this as a profile script, not system-wide install
cat > /etc/profile.d/developer-hints.sh << 'EOF'
# MyDistro Developer Edition
# Run 'flatpak install flathub com.visualstudio.code' to install VS Code
# Run 'nvm install --lts' if you need multiple Node versions
EOF

# Oh My Zsh is not installed system-wide, but set zsh as available
chsh -s /usr/bin/zsh root 2>/dev/null || true
```

```bash
chmod +x editions/developer/hooks/01-developer-setup.hook.chroot
```

---

## Step 2.5 — Add Custom APT Repository (Optional)

If you have your own `.deb` packages, add your repo to the common base:

Create `common/archives/mydistro.list.chroot`:
```
deb [signed-by=/usr/share/keyrings/mydistro-archive-keyring.gpg] https://pkg.mydistro.example.com/apt stable main
```

Create `common/archives/mydistro.key.chroot`:
```bash
# Export your GPG public key in armored format:
gpg --export --armor YOUR_KEY_ID > common/archives/mydistro.key.chroot
```

> If you don't have packages to host yet, skip this step entirely.

---

## Step 2.6 — Build and Verify All Three Editions (amd64)

```bash
make server ARCH=amd64
make desktop ARCH=amd64
make developer ARCH=amd64
```

### What to verify per edition

#### Server
```bash
qemu-system-x86_64 -m 1024 -cdrom output/mydistro-1.0-server-amd64.iso -boot d -nographic
# After boot:
dpkg -l | grep xfce4     # Should return nothing
systemctl status ufw      # Should be active
systemctl status sshd     # Should be active
cat /etc/os-release       # Should show MyDistro
```

#### Desktop
```bash
qemu-system-x86_64 -m 4096 -cdrom output/mydistro-1.0-desktop-amd64.iso -boot d \
  -vga virtio -display gtk
# After boot:
# - LightDM login screen should appear
# - Log in (live session user, no password)
# - XFCE desktop should load
flatpak --version         # Should be present
```

#### Developer
```bash
# Same as desktop, plus:
docker --version          # Should be present
git --version
python3 --version
node --version
```

---

## Step 2.7 — ARM64 Build and Verify

```bash
# Build all editions for arm64
make server ARCH=arm64
make desktop ARCH=arm64
make developer ARCH=arm64
```

### Test server arm64 in QEMU
```bash
qemu-system-aarch64 \
  -machine virt \
  -cpu cortex-a57 \
  -m 2048 \
  -bios /usr/share/qemu-efi-aarch64/QEMU_EFI.fd \
  -cdrom output/mydistro-1.0-server-arm64.iso \
  -nographic

# Install qemu-efi-aarch64 if needed:
sudo apt install qemu-efi-aarch64
```

### Common arm64 build issues

| Issue | Fix |
|---|---|
| Package not available for arm64 | Check `apt-cache search <pkg>` on an arm64 machine or in Ubuntu package search. Remove from list or find arm64 alternative. |
| `binfmt` errors during chroot | `sudo systemctl restart binfmt-support` then retry |
| `qemu-user-static` not found in chroot | Add `qemu-user-static` to `base.list` |
| Bootloader fails | Ensure `grub-efi-arm64-bin` is installed on the build host |

---

## Step 2.8 — Commit

```bash
git add .
git commit -m "feat: add package lists and setup hooks for all three editions"
git push origin dev
```

---

## Checklist

- [ ] `common/package-lists/base.list` finalized
- [ ] `common/hooks/base/01-unattended-upgrades.hook.chroot` created and executable
- [ ] Server package list created, hardening hook created and executable
- [ ] Desktop package list created with XFCE + Flatpak packages
- [ ] Desktop setup hook created and executable
- [ ] Developer package list created (superset of desktop + dev tools)
- [ ] Developer setup hook created and executable (Docker group, zsh)
- [ ] All three editions build successfully on amd64
- [ ] Server ISO verified: no GUI, ufw active, SSH active
- [ ] Desktop ISO verified: XFCE loads, Flatpak present
- [ ] Developer ISO verified: Docker, Git, Node, Python present
- [ ] All three editions build successfully on arm64
- [ ] ARM64 server ISO boots in QEMU
- [ ] Changes committed to `dev`

---

## Next Step

→ [Phase 3: Branding](PHASE3_BRANDING.md)
