# MyDistro — Setup & Maintenance Plan

---

## Overview

An Ubuntu 24.04 LTS-based distribution with three editions:

| Edition | GUI | Flatpak | Target User |
|---|---|---|---|
| Server | No | No | Sysadmins, headless deployments |
| Desktop | XFCE | Yes | General users |
| Developer | XFCE | Yes | Developers |

All editions support **amd64** and **arm64**. Desktop and Developer editions use **Calamares** as the installer with post-install Flatpak provisioning.

---

## Phase 1: Foundation (Week 1–2)

### 1.1 Repository Setup

- Create a Git repo (GitHub or GitLab) — single source of truth
- Branch strategy:
  - `main` — stable, always buildable
  - `dev` — active development
  - `release/1.0`, `release/1.1` — version branches for LTS support

### 1.2 Install Build Dependencies

```bash
sudo apt install live-build calamares \
  qemu-user-static binfmt-support \
  git make curl
```

### 1.3 Repo Structure

```
my-distro/
├── common/
│   ├── package-lists/base.list
│   ├── hooks/base/
│   │   └── 01-flatpak-setup.hook.chroot
│   └── includes.chroot/
│       ├── etc/os-release
│       ├── etc/apt/sources.list
│       └── usr/share/backgrounds/mydistro/
├── editions/
│   ├── server/
│   │   ├── lb-config
│   │   └── package-lists/server.list
│   ├── desktop/
│   │   ├── lb-config
│   │   ├── package-lists/desktop.list
│   │   └── includes.chroot/
│   │       ├── etc/calamares/
│   │       └── usr/lib/mydistro/flatpak-install-desktop.sh
│   └── developer/
│       ├── lb-config
│       ├── package-lists/developer.list
│       └── includes.chroot/
│           ├── etc/calamares/
│           └── usr/lib/mydistro/flatpak-install-developer.sh
├── branding/
│   ├── sources/              # SVG originals
│   ├── plymouth/             # boot splash
│   ├── grub/                 # bootloader theme
│   └── xfce/                 # GTK theme, icons, wallpaper
├── Makefile
└── .github/workflows/build.yml
```

---

## Phase 2: Base System (Week 2–3)

### 2.1 Common Base

- Configure `lb config` defaults — Ubuntu Noble 24.04 LTS, apt sources, locale
- Define `base.list`: packages common to all editions
- Set `etc/os-release` with distro name and version
- Add Ubuntu repos + optional custom repo to `sources.list`

**`common/package-lists/base.list`**
```
openssh-server
curl
wget
ca-certificates
apt-transport-https
unattended-upgrades
sudo
bash-completion
ufw
```

### 2.2 Edition Package Lists

**`editions/server/package-lists/server.list`**
```
fail2ban
htop
tmux
vim
```

**`editions/desktop/package-lists/desktop.list`**
```
xfce4
xfce4-goodies
lightdm
lightdm-gtk-greeter
network-manager-gnome
xdg-user-dirs
flatpak
xdg-desktop-portal-gtk
```

**`editions/developer/package-lists/developer.list`**
```
xfce4
xfce4-goodies
lightdm
lightdm-gtk-greeter
network-manager-gnome
xdg-user-dirs
flatpak
xdg-desktop-portal-gtk
git
gh
build-essential
cmake
python3-pip
python3-venv
nodejs
npm
docker.io
docker-compose-plugin
```

### 2.3 ARM Support

- Add `--architectures arm64` to each edition's `lb-config`
- Test server edition on ARM first (simplest — no GUI)
- Use QEMU on x86 host for cross-builds, or native ARM CI runners

---

## Phase 3: Branding (Week 3–4)

### 3.1 Core Assets to Create

- Logo — SVG source, exported to PNG at 32, 64, 128, 256px
- Wallpaper — 1920×1080 minimum, 3840×2160 for HiDPI
- Color palette — primary, secondary, accent colors

### 3.2 Branding Layers

#### GRUB

```
/boot/grub/themes/mydistro/
├── theme.txt
├── background.png
└── fonts/
```

```bash
# /etc/default/grub
GRUB_THEME="/boot/grub/themes/mydistro/theme.txt"
GRUB_DISTRIBUTOR="MyDistro"
```

#### Plymouth (boot splash)

```
/usr/share/plymouth/themes/mydistro/
├── mydistro.plymouth
├── mydistro.script
├── logo.png
└── progress bar assets
```

#### LightDM (login screen)

```ini
# /etc/lightdm/lightdm-gtk-greeter.conf
[greeter]
background=/usr/share/backgrounds/mydistro/wallpaper.png
theme-name=MyDistro
icon-theme-name=MyDistro
logo=/usr/share/mydistro/logo.png
```

#### XFCE

- GTK theme — inherit Greybird, override colors and assets
- Icon theme — inherit Papirus or Hicolor, add custom icons
- Default wallpaper via `xfce4-desktop.xml`
- Panel layout via `xfce4-panel.xml`

```
/usr/share/themes/MyDistro/
├── gtk-2.0/gtkrc
├── gtk-3.0/gtk.css
└── xfwm4/
    ├── themerc
    └── *.xpm
```

#### os-release

```ini
NAME="MyDistro"
VERSION="1.0"
ID=mydistro
ID_LIKE=ubuntu
PRETTY_NAME="MyDistro 1.0"
HOME_URL="https://mydistro.example.com"
```

---

## Phase 4: Installer (Week 4–5)

### 4.1 Calamares Configuration

- Base config from `calamares-settings-ubuntu`
- Customize `branding.desc` — name, logo, URLs, slideshow
- Configure `settings.conf` module sequence
- Add per-edition `shellprocess-flatpak-apps.conf`

**`branding.desc`**
```yaml
componentName: mydistro
strings:
  productName: "MyDistro"
  shortProductName: "MyDistro"
  version: "1.0"
  shortVersion: "1.0"
  versionedName: "MyDistro 1.0"
  shortVersionedName: "MyDistro 1.0"
  bootloaderEntryName: "MyDistro"
  productUrl: "https://mydistro.example.com"
  supportUrl: "https://mydistro.example.com/support"
  releaseNotesUrl: "https://mydistro.example.com/notes"
```

**`settings.conf` exec sequence (Desktop/Developer)**
```yaml
- exec:
  - partition
  - mount
  - unpackfs
  - machineid
  - fstab
  - locale
  - keyboard
  - localecfg
  - users
  - displaymanager
  - networkcfg
  - hwclock
  - grubcfg
  - bootloader
  - packages
  - shellprocess-flatpak        # add Flathub remote
  - shellprocess-flatpak-apps   # install edition apps
  - umount
```

### 4.2 Flatpak Post-Install Scripts

**Network check (top of every script)**
```bash
if ! curl -sf --max-time 5 https://dl.flathub.org > /dev/null 2>&1; then
    echo "No network — skipping Flatpak installs. Run 'flatpak install flathub <app>' after connecting."
    exit 0
fi
```

**`flatpak-install-desktop.sh`**
```bash
#!/bin/bash
set -euo pipefail

# network check here ...

APPS=(
    "org.mozilla.firefox"
    "org.libreoffice.LibreOffice"
    "org.videolan.VLC"
    "com.github.tchx84.Flatseal"
)

flatpak remote-add --system --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo

for app in "${APPS[@]}"; do
    flatpak install --system --noninteractive flathub "$app" || \
        echo "WARNING: Failed to install $app, skipping."
done
```

**`flatpak-install-developer.sh`**
```bash
#!/bin/bash
set -euo pipefail

# network check here ...

# Install desktop apps first
bash /usr/lib/mydistro/flatpak-install-desktop.sh

DEV_APPS=(
    "com.visualstudio.code"
    "io.podman_desktop.PodmanDesktop"
    "rest.insomnia.Insomnia"
    "io.dbeaver.DBeaverCommunity"
)

for app in "${DEV_APPS[@]}"; do
    flatpak install --system --noninteractive flathub "$app" || \
        echo "WARNING: Failed to install $app, skipping."
done
```

**`modules/shellprocess-flatpak.conf`**
```yaml
dontChroot: false
timeout: 300
script:
  - "-": "flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo"
```

**`modules/shellprocess-flatpak-apps.conf`**
```yaml
dontChroot: false
timeout: 600
script:
  - "-": "/usr/lib/mydistro/flatpak-install-<edition>.sh"
```

> Each edition ships its own version of this file pointing to the correct script.

### 4.3 Installer Testing Checklist

- [ ] Desktop install with network — Flatpak apps install correctly
- [ ] Desktop install without network — completes cleanly, user sees message
- [ ] Developer install with network — all dev Flatpaks install
- [ ] Server install — no Calamares, no Flatpak
- [ ] ARM install in QEMU arm64

---

## Phase 5: CI/CD Pipeline (Week 5–6)

### 5.1 Build Matrix

6 ISO artifacts per release:

```
server    × amd64
server    × arm64
desktop   × amd64
desktop   × arm64
developer × amd64
developer × arm64
```

### 5.2 GitHub Actions Workflow

**`.github/workflows/build.yml`**
```yaml
name: Build ISOs

on:
  push:
    branches: [main, dev]
  create:
    tags:
      - 'v*'

jobs:
  build:
    strategy:
      matrix:
        edition: [server, desktop, developer]
        arch: [amd64, arm64]
    runs-on: ${{ matrix.arch == 'arm64' && 'ubuntu-24.04-arm' || 'ubuntu-24.04' }}
    steps:
      - uses: actions/checkout@v4

      - name: Install live-build
        run: sudo apt install -y live-build

      - name: Build ISO
        run: make ${{ matrix.edition }} ARCH=${{ matrix.arch }}

      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: mydistro-${{ matrix.edition }}-${{ matrix.arch }}
          path: output/*.iso
```

### 5.3 Makefile

```makefile
EDITIONS := server desktop developer
ARCH ?= amd64

.PHONY: all $(EDITIONS) clean

all: $(EDITIONS)

$(EDITIONS):
	@echo "Building $@ edition..."
	mkdir -p build/$@ output
	cp -r common/. build/$@/
	cp -r editions/$@/. build/$@/
	cd build/$@ && lb config $(shell cat editions/$@/lb-config) --architectures $(ARCH)
	cd build/$@ && lb build
	mv build/$@/live-image-$(ARCH).hybrid.iso \
	   output/mydistro-$@-$(ARCH).iso

arm64:
	$(MAKE) ARCH=arm64

clean:
	rm -rf build/ output/
```

### 5.4 Build Triggers

| Trigger | Action |
|---|---|
| Push to `dev` | Build all editions, upload as artifacts (not published) |
| Push to `main` | Build + smoke tests |
| Git tag `v*` | Full release build → publish ISOs + checksums |

### 5.5 Smoke Tests

- Boot ISO in QEMU headless — verify installer starts
- Server edition: verify SSH reachable after unattended install
- Check `os-release` contains correct distro name and version

---

## Phase 6: Distribution

### 6.1 Release Artifacts

```
mydistro-1.0-server-amd64.iso
mydistro-1.0-server-arm64.iso
mydistro-1.0-desktop-amd64.iso
mydistro-1.0-desktop-arm64.iso
mydistro-1.0-developer-amd64.iso
mydistro-1.0-developer-arm64.iso
SHA256SUMS
SHA256SUMS.gpg
```

Sign with a dedicated distro GPG key:
```bash
gpg --armor --detach-sign SHA256SUMS
```

### 6.2 Hosting Options

| Option | Best For |
|---|---|
| GitHub Releases | Small distros, simple setup, free |
| Self-hosted nginx + rsync | Full control, custom mirror network |
| Torrent seeding | Bandwidth relief for popular releases |

---

## Ongoing Maintenance

### Monthly

- [ ] Review Ubuntu security advisories
- [ ] Rebuild ISOs — `lb build` picks up latest package versions automatically
- [ ] Verify Flathub app IDs haven't changed (apps occasionally rename)
- [ ] Re-sign `SHA256SUMS` if ISOs are republished

### Per Ubuntu LTS Release (every 2 years)

- [ ] Create new `release/X.0` branch
- [ ] Update `lb-config` to new Ubuntu codename
- [ ] Test all three editions end-to-end
- [ ] Update Calamares if new version available
- [ ] Maintain previous LTS branch for ~12 months overlap

### Components to Monitor

| Component | Watch For |
|---|---|
| Ubuntu base | LTS EOL dates, security notices |
| Calamares | New releases — installer bugs and features |
| Flathub | App ID changes, new recommended apps |
| live-build | Ubuntu/Debian build tooling changes |
| XFCE | Major version releases (4.x) |
| Docker | API/package changes affecting developer edition |

---

## Version Numbering

```
1.0   — initial release (Ubuntu 24.04 base)
1.1   — point release (package updates, bug fixes, new Flatpak defaults)
1.2   — point release
2.0   — rebase on next Ubuntu LTS
```

---

## Summary Timeline

| Week | Milestone |
|---|---|
| 1–2 | Repo scaffolded, base `lb build` produces bootable ISO |
| 3 | All three editions build successfully |
| 4 | Branding applied (GRUB, Plymouth, XFCE, LightDM) |
| 5 | Calamares installer works, Flatpak post-install scripts tested |
| 6 | CI/CD pipeline live, ARM builds passing |
| 7+ | Hardware testing, polish, first public release |

---

## Detailed Phase Documents

Each phase has a full step-by-step guide with every command, config file, and verification checklist:

| Phase | Document | Contents |
|---|---|---|
| 0 — Environment | [phases/PHASE0_ENVIRONMENT.md](phases/PHASE0_ENVIRONMENT.md) | QEMU build VM, snapshots, shared repo mount |
| 1 — Foundation | [phases/PHASE1_FOUNDATION.md](phases/PHASE1_FOUNDATION.md) | Git repo, build deps, scaffold, first ISO |
| 2 — Base System | [phases/PHASE2_BASE_SYSTEM.md](phases/PHASE2_BASE_SYSTEM.md) | Package lists, hooks, ARM64 builds |
| 3 — Branding | [phases/PHASE3_BRANDING.md](phases/PHASE3_BRANDING.md) | GRUB, Plymouth, LightDM, XFCE theme |
| 4 — Installer | [phases/PHASE4_INSTALLER.md](phases/PHASE4_INSTALLER.md) | Calamares config, Flatpak post-install scripts |
| 5 — CI/CD | [phases/PHASE5_CICD.md](phases/PHASE5_CICD.md) | GitHub Actions, signing, release workflow |
| 6 — Distribution | [phases/PHASE6_DISTRIBUTION.md](phases/PHASE6_DISTRIBUTION.md) | Hosting, maintenance schedule, LTS rebase |
