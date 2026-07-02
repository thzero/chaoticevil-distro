# ChaoticEvil Linux — Debian Build Plan

An alternative to the Ubuntu-based plan in [DISTRO_PLAN.md](DISTRO_PLAN.md), targeting **Debian Testing (trixie)** as the base instead of Ubuntu 24.04 LTS. The pipeline is identical; the differences are in `lb config` parameters, package names, and Calamares configuration.

---

## Why Debian Testing?

| | Ubuntu 24.04 LTS | Debian Testing (trixie) |
|---|---|---|
| Package freshness | Fixed at April 2024 snapshot | Rolling — packages update continuously |
| Default kernel | Ubuntu HWE 6.8 | Debian 6.12 LTS |
| Non-free firmware | Separate `universe` | `non-free-firmware` area, on by default |
| `live-build` support | Via Ubuntu adaptations | Native — live-build is a Debian project |
| Calamares helpers | `calamares-settings-ubuntu` | Must configure manually |
| Long-term support | Ubuntu LTS cycle (5 years) | Until Debian 14 (~2029) |
| Audio stack | PulseAudio or PipeWire | PipeWire (default in trixie) |

**Testing vs Sid:**
- **trixie (Testing)** — Recommended. Packages migrate from Sid after 10 days with no RC bugs. Reasonable stability for end users.
- **sid (Unstable)** — Packages land immediately. Can break mid-cycle. Change `DEBIAN_CODENAME=sid` in `distro.conf` to target it.

---

## What stays the same

| Phase | Status | Notes |
|---|---|---|
| Phase 0 — Build VM | **Unchanged** | Same QEMU scripts, Ubuntu build host |
| Phase 3 — Branding | **Minor delta** | `ID_LIKE=debian` in os-release; no `plymouth-theme-ubuntu-text` |
| Phase 5 — CI/CD | **Unchanged** | GitHub Actions matrix build identical |
| Phase 6 — Distribution | **Unchanged** | ISO hosting, GPG signing, apt repo, maintenance calendar |

## What changes

| Phase | Status | Notes |
|---|---|---|
| Phase 1 — Foundation | **New lb config** | Debian mirrors, `trixie`, `non-free-firmware`, kernel flavour `amd64` not `generic` |
| Phase 2 — Base system | **Package deltas** | Remove Ubuntu-specific packages; Debian origin strings in hooks |
| Phase 4 — Installer | **Full manual config** | No `calamares-settings-ubuntu`; write `settings.conf` from scratch |

---

## Phase 0 — Build Environment

**No changes.** Use the existing scripts as-is:

- [`ubuntu/scripts/phase0-host.sh`](../ubuntu/scripts/phase0-host.sh)
- [`ubuntu/scripts/phase0-post-install.sh`](../ubuntu/scripts/phase0-post-install.sh)
- [`ubuntu/scripts/phase0-vm.sh`](../ubuntu/scripts/phase0-vm.sh)

The build host runs Ubuntu. `live-build` on Ubuntu targeting Debian is fully supported — `debootstrap` handles the bootstrap regardless of the build host distro.

→ See [PHASE0_ENVIRONMENT.md](../PHASE0_ENVIRONMENT.md)

---

## Phase 1 — Foundation

Key changes from the Ubuntu lb config:

- `--distribution trixie` (not `noble`)
- `--archive-areas "main contrib non-free non-free-firmware"` (not Ubuntu's `main restricted universe multiverse`)
- No `--parent-distribution` or `--parent-archive-areas` (Ubuntu-specific)
- Mirrors: `deb.debian.org` and `security.debian.org`
- `--linux-flavours amd64` or `arm64` (not `generic`)

→ See [phases/PHASE1_FOUNDATION.md](phases/PHASE1_FOUNDATION.md)

---

## Phase 2 — Base System

Package list changes:

| Remove (Ubuntu-only) | Reason |
|---|---|
| `friendly-recovery` | Ubuntu-only package |
| `update-manager-core` | Ubuntu-only |
| `plymouth-theme-ubuntu-text` | Ubuntu-only; use custom theme |
| `command-not-found` | Ubuntu-specific behaviour |
| `linux-image-generic` / `linux-headers-generic-hwe-24.04` | Debian kernel names differ |

Package substitutions:

| Ubuntu | Debian |
|---|---|
| `pulseaudio` | `pipewire` + `pipewire-pulse` + `wireplumber` |
| `openjdk-21-jdk` | `default-jdk` |
| `golang-go` | `golang` |
| `calamares-settings-ubuntu` | (removed — manual config in Phase 4) |
| `calamares-data` | (removed — not a Debian package) |

Hook changes:
- `01-unattended-upgrades.hook.chroot`: origin strings use `Debian:trixie-security` not `Ubuntu`
- `02-mainline-kernel.hook.chroot`: removal target is `linux-image-${PKG_ARCH}` not `linux-image-generic`

→ See [phases/PHASE2_BASE_SYSTEM.md](phases/PHASE2_BASE_SYSTEM.md)

---

## Phase 3 — Branding

Follow [ubuntu/phases/PHASE3_BRANDING.md](../ubuntu/phases/PHASE3_BRANDING.md) with two changes:

**`common/includes.chroot/etc/os-release`** — use `ID_LIKE=debian`:
```
ID_LIKE=debian
```

**Plymouth** — `plymouth-theme-ubuntu-text` does not exist on Debian. Install `plymouth-themes` for generic built-in options, or build a custom theme (covered in Phase 3). The custom theme process is identical.

---

## Phase 4 — Installer (Calamares)

No `calamares-settings-ubuntu` on Debian. Every configuration file is written manually:

```
/etc/calamares/
├── settings.conf
├── branding/chaoticevil/
└── modules/
    ├── unpackfs.conf
    ├── users.conf
    ├── partition.conf
    ├── displaymanager.conf
    ├── grubcfg.conf
    └── shellprocess.conf
```

→ See [phases/PHASE4_INSTALLER.md](phases/PHASE4_INSTALLER.md)

---

## Phase 5 — CI/CD

**No changes.** The GitHub Actions matrix build is identical. Just ensure the Makefile `lb config` call uses the Debian parameters from Phase 1.

---

## Phase 6 — Distribution

**No changes.** ISO hosting, GPG signing, `chaoticevil-branding` apt package, and maintenance calendar are all identical.

**Rebase cycle** (Debian instead of Ubuntu LTS):
- When trixie freezes and becomes Debian 13 (~2027): the `trixie` codename stays valid — the archive just moves from `testing` to `stable`. No config change needed.
- Debian 14 (~2029): update `DEBIAN_CODENAME=forky` (or whatever the next codename is) in `distro.conf`, re-run branding script, test all 6 ISOs, tag v2.0.

---

## Configuration

Debian-specific values in [`distro.conf`](distro.conf):

```bash
DEBIAN_CODENAME="trixie"                    # trixie=Testing, sid=Unstable, bookworm=Stable
DEBIAN_ARCHIVE_AREAS="main contrib non-free non-free-firmware"
```

---

## Editions

Same three editions as the Ubuntu plan:

| Edition | GUI | Flatpak | Target user |
|---|---|---|---|
| **Server** | No | No | Sysadmins, headless deployments |
| **Desktop** | XFCE | Yes | General users |
| **Developer** | XFCE | Yes | Developers |

Both **amd64** and **arm64**.

---

## Checklist

- [ ] `distro.conf` — `DEBIAN_CODENAME` and `DEBIAN_ARCHIVE_AREAS` set
- [ ] Phase 1: `lb config` uses Debian mirrors and `trixie`
- [ ] Phase 1: Makefile `FLAVOUR` logic handles `amd64`/`arm64` (not `generic`)
- [ ] Phase 2: Package lists — no Ubuntu-specific packages
- [ ] Phase 2: `01-unattended-upgrades` hook — Debian origin strings
- [ ] Phase 2: `02-mainline-kernel` hook — `linux-image-${PKG_ARCH}` removal target
- [ ] Phase 2: `os-release` — `ID_LIKE=debian`
- [ ] Phase 2: Desktop list uses PipeWire, not PulseAudio
- [ ] Phase 3: Plymouth theme works without `plymouth-theme-ubuntu-text`
- [ ] Phase 4: `settings.conf` written and valid
- [ ] Phase 4: All Calamares modules configured
- [ ] Phase 4: Post-install Flatpak script runs after install
- [ ] All 6 ISOs build and boot
- [ ] `dpkg -l | grep ubuntu` returns nothing in installed system
