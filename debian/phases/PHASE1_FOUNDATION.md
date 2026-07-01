# Phase 1: Foundation (Debian)

**Goal**: Same as the Ubuntu plan — `make desktop ARCH=amd64` produces a bootable Debian-based ISO.

**Prerequisite**: [Phase 0](../../ubuntu/phases/PHASE0_ENVIRONMENT.md) complete — build VM running, repo mounted inside VM.

**Differences from [ubuntu/phases/PHASE1_FOUNDATION.md](../../ubuntu/phases/PHASE1_FOUNDATION.md)**:
- `lb config` uses Debian mirrors and `trixie`
- Archive areas: `main contrib non-free non-free-firmware`
- No `--parent-distribution` or `--parent-archive-areas` (Ubuntu-specific parameters)
- Kernel flavour: `amd64` / `arm64` (not `generic`)

Steps 1.1 (Git repo), 1.2 (build deps), and 1.3 (repo structure) are **identical** to the Ubuntu plan — see [ubuntu/phases/PHASE1_FOUNDATION.md](../../ubuntu/phases/PHASE1_FOUNDATION.md).

---

## Step 1.4 — lb config (Debian)

Each edition has its own `lb-config` file. The Makefile sources it before running `lb build`.

### `editions/server/lb-config` (amd64)

```bash
#!/bin/sh
lb config noauto \
  --distribution "trixie" \
  --archive-areas "main contrib non-free non-free-firmware" \
  --mirror-bootstrap "http://deb.debian.org/debian" \
  --mirror-chroot "http://deb.debian.org/debian" \
  --mirror-chroot-security "http://security.debian.org/debian-security" \
  --mirror-binary "http://deb.debian.org/debian" \
  --mirror-binary-security "http://security.debian.org/debian-security" \
  --security true \
  --updates true \
  --backports false \
  --binary-images iso-hybrid \
  --bootappend-live "boot=live components quiet splash" \
  --linux-flavours amd64 \
  --architectures amd64 \
  "${@}"
```

```bash
chmod +x editions/server/lb-config
```

### `editions/server/lb-config` (arm64)

Replace `--linux-flavours amd64 --architectures amd64` with:
```bash
  --linux-flavours arm64 \
  --architectures arm64 \
```

Desktop and Developer editions use the same lb-config structure — the Makefile layers their package lists and hooks on top.

### Key differences from Ubuntu lb-config

| Parameter | Ubuntu | Debian |
|---|---|---|
| `--distribution` | `noble` | `trixie` |
| `--archive-areas` | `main restricted universe multiverse` | `main contrib non-free non-free-firmware` |
| `--mirror-bootstrap` | `http://archive.ubuntu.com/ubuntu` | `http://deb.debian.org/debian` |
| `--mirror-chroot-security` | `http://security.ubuntu.com/ubuntu` | `http://security.debian.org/debian-security` |
| `--linux-flavours` | `generic` | `amd64` or `arm64` |
| `--parent-distribution` | `noble` | *not used* |
| `--parent-archive-areas` | `main restricted universe multiverse` | *not used* |

---

## Step 1.5 — Makefile (Debian)

```makefile
DISTRO  := chaoticevil
VERSION := 1.0
DIST    := trixie
ARCH    ?= amd64

# Debian kernel flavour name matches arch name, not 'generic'
ifeq ($(ARCH),amd64)
  FLAVOUR := amd64
else ifeq ($(ARCH),arm64)
  FLAVOUR := arm64
else
  $(error Unsupported ARCH=$(ARCH). Use ARCH=amd64 or ARCH=arm64)
endif

OUTPUT := output
.PHONY: server desktop developer clean

$(OUTPUT):
	mkdir -p $(OUTPUT)

server: $(OUTPUT)
	$(MAKE) _lb_config
	rsync -a editions/server/package-lists/ config/package-lists/
	rsync -a editions/server/hooks/         config/hooks/live/    2>/dev/null || true
	lb build
	mv binary.hybrid.iso $(OUTPUT)/$(DISTRO)-$(VERSION)-server-$(ARCH).iso

desktop: $(OUTPUT)
	$(MAKE) _lb_config
	rsync -a editions/desktop/package-lists/   config/package-lists/
	rsync -a editions/desktop/hooks/           config/hooks/live/    2>/dev/null || true
	rsync -a editions/desktop/includes.chroot/ config/includes.chroot/ 2>/dev/null || true
	lb build
	mv binary.hybrid.iso $(OUTPUT)/$(DISTRO)-$(VERSION)-desktop-$(ARCH).iso

developer: $(OUTPUT)
	$(MAKE) _lb_config
	rsync -a editions/developer/package-lists/   config/package-lists/
	rsync -a editions/developer/hooks/           config/hooks/live/    2>/dev/null || true
	rsync -a editions/developer/includes.chroot/ config/includes.chroot/ 2>/dev/null || true
	lb build
	mv binary.hybrid.iso $(OUTPUT)/$(DISTRO)-$(VERSION)-developer-$(ARCH).iso

_lb_config:
	lb clean
	mkdir -p config/package-lists config/hooks/live config/includes.chroot
	lb config noauto \
	  --distribution "$(DIST)" \
	  --archive-areas "main contrib non-free non-free-firmware" \
	  --mirror-bootstrap "http://deb.debian.org/debian" \
	  --mirror-chroot "http://deb.debian.org/debian" \
	  --mirror-chroot-security "http://security.debian.org/debian-security" \
	  --mirror-binary "http://deb.debian.org/debian" \
	  --mirror-binary-security "http://security.debian.org/debian-security" \
	  --security true --updates true --backports false \
	  --binary-images iso-hybrid \
	  --bootappend-live "boot=live components quiet splash" \
	  --linux-flavours "$(FLAVOUR)" \
	  --architectures "$(ARCH)"
	rsync -a common/package-lists/  config/package-lists/
	rsync -a common/hooks/base/     config/hooks/live/
	rsync -a common/includes.chroot/ config/includes.chroot/ 2>/dev/null || true

clean:
	lb clean --purge
```

---

## Step 1.6 — APT sources (Debian deb822 format)

Debian trixie uses deb822 `.sources` format. `lb config` generates the primary sources automatically. If you need to add a custom repo for your branding package, create `common/includes.chroot/etc/apt/sources.list.d/chaoticevil.sources`:

```
Types: deb
URIs: https://pkg.chaoticevil.thzero.com/apt
Suites: trixie
Components: main
Signed-By: /usr/share/keyrings/chaoticevil-archive-keyring.gpg
```

The main Debian sources are managed by `lb config` — do not duplicate them here.

---

## Step 1.7 — os-release (Debian)

`common/includes.chroot/etc/os-release`:

```
NAME="ChaoticEvil Linux"
VERSION="1.0 (Jade Juiblex)"
ID=chaoticevil
ID_LIKE=debian
PRETTY_NAME="ChaoticEvil Linux 1.0 (Jade Juiblex)"
VERSION_ID="1.0"
HOME_URL="https://chaoticevil.thzero.com"
SUPPORT_URL="https://chaoticevil.thzero.com/support"
BUG_REPORT_URL="https://chaoticevil.thzero.com/issues"
```

Note `ID_LIKE=debian` — this affects tools that check for Ubuntu compatibility. Any Ubuntu-specific tooling that reads `ID_LIKE` will correctly not activate.

---

## Step 1.8 — Verify first build

```bash
# Inside the build VM:
cd ~/distro-repo
make server ARCH=amd64
# Expect: output/chaoticevil-1.0-server-amd64.iso

# Quick boot test:
qemu-system-x86_64 \
  -m 2048 -smp 2 \
  -cdrom output/chaoticevil-1.0-server-amd64.iso \
  -boot d -enable-kvm \
  -nographic

# After boot prompt:
cat /etc/os-release     # Should show ChaoticEvil, ID_LIKE=debian
dpkg -l | grep ubuntu   # Should return nothing
uname -r                # Should show mainline kernel version
```

---

## Checklist

- [ ] `editions/*/lb-config` created with Debian mirrors and `trixie`
- [ ] Makefile `FLAVOUR` logic: `amd64`/`arm64`, not `generic`
- [ ] `make server ARCH=amd64` completes without errors
- [ ] `make server ARCH=arm64` completes without errors
- [ ] `os-release` shows `ID_LIKE=debian`
- [ ] `dpkg -l | grep ubuntu` returns nothing
- [ ] Changes committed to `dev`
