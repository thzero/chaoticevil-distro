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

### Mainline kernel hook

By default, live-build installs `linux-image-generic` (Ubuntu's standard kernel). To ship a mainline kernel from the [Ubuntu Kernel Archive](https://kernel.ubuntu.com/mainline/) instead, add a chroot hook that downloads and installs it during the build.

**Why a hook and not a package list entry**: mainline builds are not in any apt repository — they are `.deb` files distributed directly from `kernel.ubuntu.com`.

> **Secure Boot note**: Mainline builds are unsigned (`linux-image-unsigned-*`). VMs and machines with Secure Boot disabled boot fine. For physical hardware with Secure Boot enabled, you must either enroll the signing key or disable Secure Boot.

Create `common/hooks/base/02-mainline-kernel.hook.chroot`:
```bash
#!/bin/bash
# Install mainline Linux kernel from the Ubuntu Kernel Archive.
# Replaces the default linux-image-generic installed by live-build.
set -e

ARCH=$(dpkg --print-architecture)
KERNEL_VERSION="7.1"   # major.minor series — latest patch fetched automatically

case "$ARCH" in
    amd64) PKG_ARCH="amd64" ;;
    arm64) PKG_ARCH="arm64" ;;
    *) echo "Mainline kernel: unsupported arch '$ARCH', skipping."; exit 0 ;;
esac

BASE_URL="https://kernel.ubuntu.com/mainline"

# Resolve the latest patch release in this series (excludes release candidates)
LATEST=$(wget -qO- "${BASE_URL}/" \
    | grep -o "v${KERNEL_VERSION}\.[0-9][0-9]*/" \
    | sort -V | tail -1 | tr -d '/')

[ -n "$LATEST" ] || { echo "ERROR: could not find mainline v${KERNEL_VERSION}.x on kernel.ubuntu.com"; exit 1; }
echo "Mainline kernel: installing ${LATEST} (${PKG_ARCH})"

DL_BASE="${BASE_URL}/${LATEST}"

# Arch-independent headers live in the version root; arch-specific packages in subdir
HDR_ALL=$(wget -qO- "${DL_BASE}/" \
    | grep -o 'href="linux-headers[^"]*_all\.deb"' \
    | sed 's/href="//;s/"$//' | head -1)

PKGS_ARCH=$(wget -qO- "${DL_BASE}/${PKG_ARCH}/" \
    | grep -o 'href="linux-[^"]*\.deb"' \
    | sed 's/href="//;s/"$//' \
    | grep -v 'lowlatency\|snapdragon\|cloud\|raspi')

[ -n "$PKGS_ARCH" ] || { echo "ERROR: no packages found at ${DL_BASE}/${PKG_ARCH}/"; exit 1; }

mkdir -p /tmp/mainline-kernel
cd /tmp/mainline-kernel

[ -n "$HDR_ALL" ] && wget -q "${DL_BASE}/${HDR_ALL}"
for pkg in $PKGS_ARCH; do
    wget -q "${DL_BASE}/${PKG_ARCH}/${pkg}"
done

dpkg -i /tmp/mainline-kernel/*.deb

# Remove the generic Ubuntu kernel to avoid bootloader conflicts and free space
apt-get remove -y --purge \
    linux-image-generic linux-headers-generic \
    linux-image-generic-hwe-24.04 linux-headers-generic-hwe-24.04 \
    2>/dev/null || true
apt-get autoremove -y

# Pin mainline packages so future apt upgrades don't silently replace them
dpkg -l | grep -E "^ii  linux-(image|headers|modules).*${KERNEL_VERSION}" \
    | awk '{print $2}' | xargs apt-mark hold 2>/dev/null || true

cd /
rm -rf /tmp/mainline-kernel
```

Make it executable:
```bash
chmod +x common/hooks/base/02-mainline-kernel.hook.chroot
```

> The `KERNEL_VERSION="7.1"` line is a substitution target for `apply-branding.sh`. Set `KERNEL_MAINLINE_VERSION` in `distro.conf` and run `./scripts/apply-branding.sh --apply` to propagate the version into this hook.

### Default shell aliases

Per-user shell defaults are seeded through the skel tree, the same way COSMIC/XFCE defaults are (see PHASE3). Ubuntu's stock `~/.bashrc` already sources `~/.bash_aliases` if it exists, so we drop a `.bash_aliases` into skel rather than overwriting `.bashrc` — this stays forward-compatible with any future Ubuntu `.bashrc` changes.

Create `common/includes.chroot/etc/skel/.bash_aliases`:
```bash
# ChaoticEvil default shell aliases
alias cd..='cd ..'
alias ll='ls -alF'
alias update='sudo apt update && sudo apt upgrade'
# ...add new aliases here
```

Every account created from skel — the Calamares install user and the live-session user — picks these up automatically. No hook is needed: at ISO build time no user accounts exist yet, so there is nothing to re-seed. To add or change an alias later, edit this one file and rebuild.

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

### Add System76 PPA (required for COSMIC)

Create `editions/desktop/archives/system76.list.chroot`:
```
deb https://ppa.launchpadcontent.net/system76-dev/stable/ubuntu noble main
```

Create `editions/developer/archives/system76.list.chroot` — same content.

Create a hook to add the PPA signing key:
`editions/desktop/hooks/00-system76-key.hook.chroot`:
```bash
#!/bin/bash
set -e
curl -fsSL https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x7F1DBDA0 | \
    gpg --dearmor -o /etc/apt/keyrings/system76.gpg
chmod 644 /etc/apt/keyrings/system76.gpg
apt-get update -q
```
```bash
chmod +x editions/desktop/hooks/00-system76-key.hook.chroot
cp editions/desktop/hooks/00-system76-key.hook.chroot \
   editions/developer/hooks/00-system76-key.hook.chroot
```

### Desktop package list

Edit `editions/desktop/package-lists/desktop.list`:
```
# COSMIC Desktop (Wayland-native, via ppa:system76-dev/stable)
cosmic-session
cosmic-comp
cosmic-panel
cosmic-settings
cosmic-files
cosmic-terminal
cosmic-launcher
cosmic-edit
cosmic-greeter
greetd

# Network
network-manager
network-manager-gnome
nm-tray

# Audio — PipeWire (required by COSMIC; replaces PulseAudio)
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

# Flatpak (COSMIC has native Flatpak/Flathub integration via cosmic-store)
flatpak
xdg-desktop-portal
xdg-desktop-portal-cosmic
xdg-user-dirs
xdg-user-dirs-gtk

# Plymouth (boot splash)
plymouth
plymouth-themes

# Calamares installer
calamares
calamares-data
```

### Desktop: configure greetd and portal hook

Create `editions/desktop/hooks/01-desktop-setup.hook.chroot`:
```bash
#!/bin/bash
set -e

# Configure greetd to launch cosmic-greeter
mkdir -p /etc/greetd
cat > /etc/greetd/config.toml << 'EOF'
[terminal]
vt = 1

[default_session]
command = "cosmic-greeter"
user = "greeter"
EOF

# Create the greeter user greetd expects
useradd -r -s /usr/sbin/nologin -d /var/lib/greeter greeter 2>/dev/null || true

# Enable greetd as the display manager
systemctl enable greetd
systemctl disable lightdm 2>/dev/null || true

# Register COSMIC session for Calamares displaymanager module
mkdir -p /usr/share/wayland-sessions
if [ ! -f /usr/share/wayland-sessions/cosmic.desktop ]; then
    cat > /usr/share/wayland-sessions/cosmic.desktop << 'EOF'
[Desktop Entry]
Name=COSMIC
Comment=COSMIC Desktop Environment
Exec=cosmic-session
Type=Application
DesktopNames=COSMIC
EOF
fi

# Set XDG portal backend for COSMIC
mkdir -p /usr/share/xdg-desktop-portal
cat > /usr/share/xdg-desktop-portal/cosmic-portals.conf << 'EOF'
[preferred]
default=cosmic;gtk
EOF

# Enable Flatpak system-wide
flatpak remote-add --system --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
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

# COSMIC Desktop (Wayland-native, via ppa:system76-dev/stable)
cosmic-session
cosmic-comp
cosmic-panel
cosmic-settings
cosmic-files
cosmic-terminal
cosmic-launcher
cosmic-edit
cosmic-greeter
greetd
network-manager
network-manager-gnome
nm-tray
pipewire
pipewire-pulse
wireplumber
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
xdg-desktop-portal-cosmic
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
xdg-desktop-portal-cosmic
xdg-user-dirs
xdg-user-dirs-gtk

Create `editions/developer/hooks/01-developer-setup.hook.chroot`:
```bash
#!/bin/bash
set -e

# Add current user to docker group (Calamares will handle the actual user)
# Add docker group so it exists for new users
groupadd -f docker

# Enable Docker service
systemctl enable docker

# Set XDG portal for COSMIC (same as desktop)
mkdir -p /usr/share/xdg-desktop-portal
cat > /usr/share/xdg-desktop-portal/cosmic-portals.conf << 'EOF'
[preferred]
default=cosmic;gtk
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

## Step 2.5 — Custom APT Repository for Post-Install Updates

Ubuntu's `unattended-upgrades` handles Ubuntu package updates automatically. But ChaoticEvil-specific files (branding, config, Flatpak app lists) are baked into the ISO at build time and have no update path unless you publish them through a custom apt repo.

This step sets up that pipeline: a GitHub Pages-hosted apt repo + a `chaoticevil-branding` package. When you update branding or configs, a GitHub Actions workflow rebuilds the repo index and publishes it automatically.

For alternative hosting options (self-hosted VPS, Google Cloud, Cloudflare), see [Appendix A](#appendix-a--apt-repo-hosting-alternatives) at the bottom of this document.

### 2.5.1 — Package ChaoticEvil branding as a .deb

Create the package skeleton:
```bash
mkdir -p packages/chaoticevil-branding/DEBIAN
mkdir -p packages/chaoticevil-branding/usr/share/backgrounds/chaoticevil
mkdir -p packages/chaoticevil-branding/usr/share/plymouth/themes/chaoticevil
mkdir -p packages/chaoticevil-branding/etc/lightdm
mkdir -p packages/chaoticevil-branding/usr/share/chaoticevil
```

Create `packages/chaoticevil-branding/DEBIAN/control`:
```
Package: chaoticevil-branding
Version: 1.0.0
Section: misc
Priority: optional
Architecture: all
Maintainer: ChaoticEvil Releases <releases@thzero.com>
Description: ChaoticEvil branding and identity assets
 Wallpapers, Plymouth theme, LightDM config, and other
 ChaoticEvil-specific customisation files.
```

Place branding assets in the tree above (`wallpaper.png` → `usr/share/backgrounds/chaoticevil/`, etc.), then build the `.deb`:
```bash
dpkg-deb --build packages/chaoticevil-branding output/chaoticevil-branding_1.0.0_all.deb
```

> Put this in the Makefile as a `make deb` target so it builds alongside the ISOs in CI.

### 2.5.2 — Set up a GitHub Pages apt repository

The apt repo is a static folder of `reprepro`-generated files committed to the `gh-pages` branch of a dedicated repo (or a subdirectory of this one).

**One-time local setup:**
```bash
# Install reprepro locally (only needed on your machine / CI runner)
sudo apt install reprepro

# Create the apt-repo directory (committed to git)
mkdir -p apt-repo/conf

cat > apt-repo/conf/distributions << 'EOF'
Origin: ChaoticEvil
Label: ChaoticEvil
Codename: stable
Architectures: amd64 arm64 all
Components: main
Description: ChaoticEvil package repository
SignWith: YOUR_GPG_KEY_ID
EOF

# Add the first .deb
reprepro -b apt-repo/ includedeb stable output/chaoticevil-branding_1.0.0_all.deb

# Commit the generated repo to a gh-pages branch
git checkout --orphan gh-pages
git rm -rf .
cp -r apt-repo/* .
git add .
git commit -m "init: apt repo"
git push origin gh-pages
git checkout main
```

Enable GitHub Pages in the repo settings → Pages → Source: `gh-pages` branch, root `/`.

Export and commit the GPG public key for users:
```bash
gpg --export --armor YOUR_GPG_KEY_ID > apt-repo/chaoticevil-archive-keyring.asc
```

The repo will be live at:
```
https://thzero.github.io/chaoticevil/
```

### 2.5.3 — Automate repo updates with GitHub Actions

Create `.github/workflows/publish-apt.yml`:
```yaml
name: Publish APT repo

on:
  release:
    types: [published]
  workflow_dispatch:

jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Install reprepro and GPG tools
        run: sudo apt-get install -y reprepro

      - name: Import GPG signing key
        run: echo "${{ secrets.APT_SIGNING_KEY }}" | gpg --import

      - name: Build .deb
        run: make deb

      - name: Checkout gh-pages
        uses: actions/checkout@v4
        with:
          ref: gh-pages
          path: gh-pages

      - name: Add .deb to repo
        run: |
          cp -r gh-pages/conf apt-repo/conf
          reprepro -b apt-repo/ includedeb stable output/chaoticevil-branding_*.deb

      - name: Deploy to gh-pages
        uses: peaceiris/actions-gh-pages@v4
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: apt-repo
          force_orphan: false
          keep_files: true
```

> **Secret required**: Add `APT_SIGNING_KEY` to the repo's Actions secrets — the GPG private key exported as ASCII armor (`gpg --export-secret-keys --armor YOUR_KEY_ID`).

### 2.5.4 — Wire the repo into installed systems

Create `common/archives/chaoticevil.list.chroot`:
```
deb [signed-by=/usr/share/keyrings/chaoticevil-archive-keyring.gpg] https://thzero.github.io/chaoticevil stable main
```

Create `common/archives/chaoticevil.key.chroot` (the exported GPG public key):
```bash
gpg --export --armor YOUR_GPG_KEY_ID > common/archives/chaoticevil.key.chroot
```

Create `common/hooks/base/02-chaoticevil-repo.hook.chroot`:
```bash
#!/bin/bash
set -e
# Convert the armored key placed by live-build into binary keyring format
gpg --dearmor < /etc/apt/trusted.gpg.d/chaoticevil.asc \
    > /usr/share/keyrings/chaoticevil-archive-keyring.gpg 2>/dev/null || true
```

```bash
chmod +x common/hooks/base/02-chaoticevil-repo.hook.chroot
```

### 2.5.5 — Enable the custom repo in unattended-upgrades

Update `common/hooks/base/01-unattended-upgrades.hook.chroot` so the full `50unattended-upgrades` block becomes:
```bash
cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "ChaoticEvil:stable";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF
```

With this in place, any time the GitHub Actions workflow publishes a new `chaoticevil-branding` version, existing installs receive it silently on their next daily `unattended-upgrades` run.

---

## Appendix A — APT Repo Hosting Alternatives

The steps above use GitHub Pages. If you need an alternative, the three options below are fully workable replacements. Only the hosting layer changes — the `.deb` packaging and `reprepro` tooling are identical.

### Option 1: Self-hosted VPS with nginx

**Best when:** You already have a VPS for ISO hosting and want everything under one domain.

```bash
# On the VPS:
sudo apt install reprepro nginx
sudo mkdir -p /var/www/apt/conf

cat << 'EOF' | sudo tee /var/www/apt/conf/distributions
Origin: ChaoticEvil
Label: ChaoticEvil
Codename: stable
Architectures: amd64 arm64 all
Components: main
Description: ChaoticEvil package repository
SignWith: YOUR_GPG_KEY_ID
EOF

# Add a .deb
sudo reprepro -b /var/www/apt includedeb stable output/chaoticevil-branding_1.0.0_all.deb

# Export signing key for users
gpg --export --armor YOUR_GPG_KEY_ID | sudo tee /var/www/apt/chaoticevil-archive-keyring.asc
```

Add to nginx server block:
```nginx
location /apt/ {
    root /var/www;
    autoindex on;
}
```

In `common/archives/chaoticevil.list.chroot`, use:
```
deb [signed-by=/usr/share/keyrings/chaoticevil-archive-keyring.gpg] https://pkg.chaoticevil.thzero.com/apt stable main
```

Deploy via GitHub Actions by SSHing into the VPS and running `reprepro includedeb` as part of the release workflow.

---

### Option 2: Google Cloud — Cloud Run + Cloud Storage

**Best when:** You want zero server management, global CDN, and pay-per-use pricing.

**Architecture:** A Cloud Storage bucket holds the repo files. Cloud Run (or just a storage bucket with public access) serves them over HTTPS.

```bash
# Create a GCS bucket
gcloud storage buckets create gs://chaoticevil-apt \
  --location=US \
  --uniform-bucket-level-access

# Make it publicly readable
gcloud storage buckets add-iam-policy-binding gs://chaoticevil-apt \
  --member=allUsers \
  --role=roles/storage.objectViewer

# Upload repo files (run reprepro locally first, then sync)
gcloud storage rsync apt-repo/ gs://chaoticevil-apt/ --recursive
```

GCS public buckets are served at:
```
https://storage.googleapis.com/chaoticevil-apt/
```

To use a custom domain (`pkg.chaoticevil.thzero.com`), point a CNAME at `c.storage.googleapis.com` and configure the bucket name to match the domain.

**GitHub Actions deployment:**
```yaml
      - name: Authenticate to Google Cloud
        uses: google-github-actions/auth@v2
        with:
          credentials_json: ${{ secrets.GCP_SA_KEY }}

      - name: Sync apt repo to GCS
        uses: google-github-actions/upload-cloud-storage@v2
        with:
          path: apt-repo/
          destination: chaoticevil-apt
```

> **Secrets required**: `GCP_SA_KEY` — a GCP service account key with `storage.objectAdmin` on the bucket.

**Cost**: GCS storage is ~$0.02/GB/month. A branding `.deb` repo will stay well under $1/month.

---

### Option 3: Cloudflare Pages

**Best when:** You already use Cloudflare for DNS and want free global CDN with DDoS protection automatically.

Cloudflare Pages serves static files from a GitHub repo, identical to GitHub Pages but routed through Cloudflare's network.

**Setup:**
1. Go to Cloudflare Dashboard → Pages → Create a project
2. Connect to your GitHub repo
3. Set branch: `gh-pages`, build command: *(none — it's pre-built)*, output directory: `/`
4. Add a custom domain: `pkg.chaoticevil.thzero.com`

The GitHub Actions workflow from Step 2.5.3 is **unchanged** — it still pushes to `gh-pages`. Cloudflare Pages picks up the push automatically and deploys within seconds.

In `common/archives/chaoticevil.list.chroot`, use your custom domain:
```
deb [signed-by=/usr/share/keyrings/chaoticevil-archive-keyring.gpg] https://pkg.chaoticevil.thzero.com stable main
```

**Advantages over raw GitHub Pages:**
- Custom domain with automatic TLS (no VPS needed)
- Global CDN — faster `apt update` worldwide
- DDoS protection built in
- Cloudflare Analytics for download stats

**Limitations:**
- 500 deployments/month on the free plan (well within limit for a small distro)
- 25 MB max per file (not a concern for `.deb` metadata files; packages are in `pool/`)

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
- [ ] `common/hooks/base/02-mainline-kernel.hook.chroot` created and executable
- [ ] Mainline kernel version confirmed in booted ISO: `uname -r` shows expected version
- [ ] `common/includes.chroot/etc/skel/.bash_aliases` created with default aliases (incl. `cd..`)
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
