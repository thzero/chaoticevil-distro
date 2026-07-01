# Phase 1: Foundation

**Goal**: A Git repository exists, build tooling is installed, and running `make desktop` produces a bootable (if unbranded) ISO.

---

## Step 1.1 — Create the Git Repository

### On GitHub/GitLab
1. Create a new **private** repo named `my-distro` (make public when ready to release)
2. Clone it locally:
```bash
git clone git@github.com:yourorg/my-distro.git
cd my-distro
```

### Create the branch structure
```bash
git checkout -b dev
git push -u origin dev
# main branch will be the default — protect it in repo settings:
# Settings → Branches → Add rule → main → Require PR before merging
```

---

## Step 1.2 — Install Build Dependencies

Run this on your **build machine** (Ubuntu 22.04 or 24.04 recommended):

```bash
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

### Verify live-build is working
```bash
lb --version
# Should print something like: live-build 20230502
```

### Enable QEMU binfmt support for ARM cross-builds
```bash
sudo systemctl enable --now binfmt-support
# Verify arm64 is registered:
ls /proc/sys/fs/binfmt_misc/ | grep aarch64
# Expected output: qemu-aarch64
```

---

## Step 1.3 — Scaffold the Repository

Run these commands from the root of your cloned repo:

```bash
# Top-level directories
mkdir -p common/package-lists
mkdir -p common/hooks/base
mkdir -p common/includes.chroot/etc/apt
mkdir -p common/includes.chroot/usr/share/backgrounds/mydistro

# Server edition
mkdir -p editions/server/package-lists
mkdir -p editions/server/includes.chroot/etc

# Desktop edition
mkdir -p editions/desktop/package-lists
mkdir -p editions/desktop/includes.chroot/etc/calamares/branding/mydistro
mkdir -p editions/desktop/includes.chroot/etc/calamares/modules
mkdir -p editions/desktop/includes.chroot/usr/lib/mydistro

# Developer edition
mkdir -p editions/developer/package-lists
mkdir -p editions/developer/includes.chroot/etc/calamares/branding/mydistro
mkdir -p editions/developer/includes.chroot/etc/calamares/modules
mkdir -p editions/developer/includes.chroot/usr/lib/mydistro

# Branding source assets
mkdir -p branding/sources
mkdir -p branding/plymouth
mkdir -p branding/grub
mkdir -p branding/xfce

# Build outputs
mkdir -p output
echo "output/" >> .gitignore
echo "build/" >> .gitignore
```

---

## Step 1.4 — Create the Common Base Files

### `common/includes.chroot/etc/apt/sources.list`
```
deb http://archive.ubuntu.com/ubuntu noble main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu noble-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu noble-security main restricted universe multiverse
```

> **ARM note**: For arm64, Ubuntu uses `ports.ubuntu.com` instead of `archive.ubuntu.com`. live-build handles this automatically when you set `--architectures arm64`, but verify the chroot has the right sources after a build.

### `common/includes.chroot/etc/os-release`
```ini
NAME="MyDistro"
VERSION="1.0"
ID=mydistro
ID_LIKE=ubuntu
PRETTY_NAME="MyDistro 1.0"
VERSION_ID="1.0"
HOME_URL="https://mydistro.example.com"
SUPPORT_URL="https://mydistro.example.com/support"
BUG_REPORT_URL="https://mydistro.example.com/issues"
LOGO=mydistro-logo
```

### `common/package-lists/base.list`
```
# Core packages for all editions
openssh-server
curl
wget
ca-certificates
apt-transport-https
gnupg
unattended-upgrades
sudo
bash-completion
ufw
```

---

## Step 1.5 — Create Edition live-build Configs

Each edition has an `lb-config` file containing extra flags passed to `lb config`.

### `editions/server/lb-config`
```
--distribution noble
--archive-areas "main restricted universe multiverse"
--debian-installer none
--bootappend-live "boot=live components quiet splash"
--linux-flavours generic
```

### `editions/desktop/lb-config`
```
--distribution noble
--archive-areas "main restricted universe multiverse"
--debian-installer none
--bootappend-live "boot=live components quiet splash"
--linux-flavours generic
--memtest none
```

### `editions/developer/lb-config`
```
--distribution noble
--archive-areas "main restricted universe multiverse"
--debian-installer none
--bootappend-live "boot=live components quiet splash"
--linux-flavours generic
--memtest none
```

---

## Step 1.6 — Create the Makefile

**`Makefile`** (repo root):
```makefile
SHELL := /bin/bash
EDITIONS := server desktop developer
ARCH ?= amd64
DISTRO_VERSION ?= 1.0

.PHONY: all $(EDITIONS) clean clean-edition

all: $(EDITIONS)

$(EDITIONS):
	@echo "==> Building $@ edition ($(ARCH))..."
	@mkdir -p build/$@ output
	@# Copy common config first, then overlay edition-specific config
	@cp -r common/. build/$@/
	@cp -r editions/$@/. build/$@/
	@cd build/$@ && lb config \
	    $(shell cat editions/$@/lb-config | tr '\n' ' ') \
	    --architectures $(ARCH) \
	    --mirror-bootstrap http://archive.ubuntu.com/ubuntu/ \
	    --mirror-binary http://archive.ubuntu.com/ubuntu/
	@cd build/$@ && lb build 2>&1 | tee ../../output/build-$@-$(ARCH).log
	@mv build/$@/live-image-$(ARCH).hybrid.iso \
	    output/mydistro-$(DISTRO_VERSION)-$@-$(ARCH).iso
	@echo "==> Done: output/mydistro-$(DISTRO_VERSION)-$@-$(ARCH).iso"

clean-edition:
	@[ -n "$(EDITION)" ] || (echo "Usage: make clean-edition EDITION=server" && exit 1)
	rm -rf build/$(EDITION)

clean:
	rm -rf build/ output/

checksums:
	@cd output && sha256sum *.iso > SHA256SUMS
	@echo "==> SHA256SUMS written"
```

---

## Step 1.7 — First Build Test (amd64 Server)

The server edition has no GUI and builds fastest — use it to verify the pipeline works:

```bash
make server ARCH=amd64
```

This will take **10–30 minutes** on first run (downloading Ubuntu base). Subsequent builds are faster due to caching.

### What to check after a successful build
```bash
# 1. ISO exists
ls -lh output/mydistro-1.0-server-amd64.iso

# 2. Boot it in QEMU to verify it starts
qemu-system-x86_64 \
  -m 2048 \
  -cdrom output/mydistro-1.0-server-amd64.iso \
  -boot d \
  -nographic \
  -serial mon:stdio

# 3. Check os-release inside the live system (once booted)
cat /etc/os-release
# Should show NAME="MyDistro" not Ubuntu
```

### Common first-build failures

| Error | Fix |
|---|---|
| `debootstrap` fails with 404 | Check Ubuntu codename in `lb-config` — `noble` is 24.04 |
| Missing `isolinux` | `sudo apt install isolinux syslinux-common` |
| `grub-efi` warnings | Install `grub-efi-amd64-bin grub-pc-bin` |
| Build hangs in chroot | Check `binfmt-support` is running: `systemctl status binfmt-support` |

---

## Step 1.8 — Commit the Scaffold

```bash
git add .
git commit -m "chore: initial repo scaffold and base live-build config"
git push origin dev
```

---

## Checklist

- [ ] Git repo created with `main` and `dev` branches
- [ ] `main` branch protected (require PR)
- [ ] All build dependencies installed
- [ ] QEMU binfmt support verified for arm64
- [ ] Repo directory structure created
- [ ] `common/` base files in place (sources.list, os-release, base.list)
- [ ] Edition `lb-config` files created for server, desktop, developer
- [ ] Makefile created and tested
- [ ] `make server ARCH=amd64` completes successfully
- [ ] ISO boots in QEMU and shows correct `os-release`
- [ ] Scaffold committed to `dev` branch

---

## Next Step

→ [Phase 2: Base System](PHASE2_BASE_SYSTEM.md)
