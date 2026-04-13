# ChaoticEvil Linux

An Ubuntu 24.04 LTS-based Linux distribution with three editions, full custom branding, automated CI/CD builds, and a complete maintenance lifecycle plan.

---

## What this repo is

A complete playbook for building, branding, and shipping a Linux distro from scratch. Everything needed — build tooling, installer config, branding assets, CI/CD pipeline, and long-term maintenance procedures — is documented and scripted here.

---

## Editions

| Edition | GUI | Flatpak apps | Target user |
|---|---|---|---|
| **Server** | No | No | Sysadmins, headless deployments |
| **Desktop** | XFCE | Yes | General users |
| **Developer** | XFCE | Yes | Developers (Git, Docker, Node, Python, etc.) |

All three editions build for **amd64** and **arm64**.

---

## What the plan builds, phase by phase

### Phase 0 — Build environment
A dedicated QEMU virtual machine that acts as the build box. One script installs Ubuntu unattended, mounts the repo into the VM, installs all build tools, and takes snapshots for rollback. You never need to rebuild from scratch if something breaks.

### Phase 1 — Repository foundation
Git repo layout, branch strategy (`main` / `dev` / `release/x.y`), Makefile build targets, and CI/CD skeleton.

### Phase 2 — Base system
Which packages go in each edition. Common base (SSH, UFW, curl, etc.) is shared; each edition adds its own layer on top — Server gets fail2ban/htop/tmux, Desktop adds XFCE + LightDM + Flatpak, Developer stacks Git, Docker, Node, Python, and more.

### Phase 3 — Branding
Every visible Ubuntu surface is replaced with ChaoticEvil visuals:
- **GRUB** — themed bootloader
- **Plymouth** — branded boot splash
- **LightDM** — custom login screen
- **XFCE** — GTK theme, icon theme, wallpaper, desktop defaults

All driven from a single [`distro.conf`](distro.conf) file. Change the name, colour, or version once — `./scripts/apply-branding.sh --apply` propagates it everywhere.

### Phase 4 — Installer
Calamares (the visual installer used by Manjaro, Fedora, etc.) configured with ChaoticEvil branding and a post-install Flatpak provisioning step. After the user completes install, selected apps are automatically installed from Flathub.

### Phase 5 — CI/CD
GitHub Actions matrix builds all 6 ISOs (3 editions × 2 arches) automatically on every push. Each release produces GPG-signed SHA256 checksums and attaches all ISOs to a GitHub Release.

### Phase 6 — Distribution and maintenance
- ISO hosting: GitHub Releases or self-hosted nginx with TLS
- Ubuntu point releases (24.04.1 → .2 → .3): monthly rebuilds pick them up automatically, no config changes needed
- Ubuntu LTS rebase (~every 2 years): update `UBUNTU_CODENAME` in `distro.conf`, re-run branding script, test all 6 ISOs, tag v2.0
- Issue templates, community setup (GitHub Discussions), and a maintenance calendar

---

## What you have when it's all done

Once all phases are implemented you have:

**6 real, installable ISOs** you can hand to someone:

```
chaoticevil-1.0-server-amd64.iso      chaoticevil-1.0-server-arm64.iso
chaoticevil-1.0-desktop-amd64.iso     chaoticevil-1.0-desktop-arm64.iso
chaoticevil-1.0-developer-amd64.iso   chaoticevil-1.0-developer-arm64.iso
```

Boot any of them on real hardware or a VM and you're in a working ChaoticEvil system — your name, your colours, your packages.

**A graphical installer** (Desktop/Developer) — Calamares walks the user through partitioning, user account, timezone, etc. After install completes, Flatpak apps silently provision themselves in the background. Server edition uses a text installer.

**A one-command local build** — `make desktop ARCH=arm64` inside the build VM. No manual steps.

**A fully automated release pipeline** — push a git tag → GitHub Actions builds and signs all 6 ISOs → attaches them to a GitHub Release with GPG-signed SHA256 checksums. Nothing to do manually.

**A maintainable distro, not a one-shot project:**
- **Ubuntu packages** — `unattended-upgrades` is pre-configured and runs daily; security patches arrive silently with no user action
- **Flatpak apps** — the built-in Flatpak update timer handles app updates automatically
- **ChaoticEvil-specific files** (branding, config, wallpapers, Flatpak app lists) — delivered via a self-hosted apt repo as a `chaoticevil-branding` `.deb`; when you push a new version, existing installs receive it on their next `apt upgrade` run
- Monthly CI rebuilds pick up Ubuntu security patches for new installs
- LTS rebase to the next Ubuntu (~26.04) is a two-line edit in `distro.conf` + a script run + a test pass

**A single knob for everything** — `distro.conf` controls the name, version, codename, accent colour, signing email, and URLs. Rebranding to a new identity is change-one-file + run-one-script.

---

## Key files

| File | Purpose |
|---|---|
| [`distro.conf`](distro.conf) | Master identity/branding config |
| [`DISTRO_PLAN.md`](DISTRO_PLAN.md) | Full phase-by-phase plan with links |
| [`scripts/apply-branding.sh`](scripts/apply-branding.sh) | Propagates distro.conf values everywhere |
| [`scripts/phase0-host.sh`](scripts/phase0-host.sh) | Sets up the build VM on the host |
| [`scripts/phase0-post-install.sh`](scripts/phase0-post-install.sh) | Completes VM setup after Ubuntu installs |
| [`scripts/phase0-vm.sh`](scripts/phase0-vm.sh) | Mounts repo and installs build deps inside VM |
| [`phases/PHASE0_ENVIRONMENT.md`](phases/PHASE0_ENVIRONMENT.md) | Build VM setup — manual + automated paths |

---

## Current status

- [x] Phase 0: Build environment documented and scripted (VM setup fully automated)
- [ ] Phase 1: Repository structure
- [ ] Phase 2: Package lists and base system
- [ ] Phase 3: Branding assets
- [ ] Phase 4: Calamares installer config
- [ ] Phase 5: CI/CD pipeline
- [ ] Phase 6: Distribution and hosting
