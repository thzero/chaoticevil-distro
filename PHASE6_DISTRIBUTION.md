# Phase 6: Distribution & Ongoing Maintenance

**Goal**: ISOs are publicly hosted and verifiable. A clear maintenance process keeps the distro up to date across Ubuntu LTS cycles.

**Prerequisite**: [Phase 5: CI/CD](PHASE5_CICD.md) complete — automated builds and releases working. (shared phase)

---

## Part A: Distribution

---

## Step 6.1 — Hosting Options

Choose one primary host. A mirror network can be added later.

### Option A: GitHub Releases (recommended to start)

Already set up in Phase 5. GitHub provides:
- Free hosting for public repos
- Direct download links
- Release notes
- Automatic file retention

**Limitation**: GitHub has a 2 GB per-file soft limit and rate-limits downloads. Fine for initial releases; revisit when download volume grows.

### Option B: Self-hosted with nginx

If you have a VPS or dedicated server:

```bash
# Install nginx
sudo apt install nginx

# Create web root
sudo mkdir -p /var/www/mydistro/releases

# Structure:
# /var/www/mydistro/
# ├── index.html
# ├── releases/
# │   ├── 1.0/
# │   │   ├── mydistro-1.0-server-amd64.iso
# │   │   ├── mydistro-1.0-server-arm64.iso
# │   │   ├── mydistro-1.0-desktop-amd64.iso
# │   │   ├── mydistro-1.0-desktop-arm64.iso
# │   │   ├── mydistro-1.0-developer-amd64.iso
# │   │   ├── mydistro-1.0-developer-arm64.iso
# │   │   ├── SHA256SUMS
# │   │   └── SHA256SUMS.asc
# │   └── latest -> 1.0/   (symlink)
# └── distro-signing-key.asc
```

**`/etc/nginx/sites-available/mydistro`**
```nginx
server {
    listen 80;
    server_name download.mydistro.example.com;

    # Redirect to HTTPS
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name download.mydistro.example.com;

    ssl_certificate     /etc/letsencrypt/live/download.mydistro.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/download.mydistro.example.com/privkey.pem;

    root /var/www/mydistro;

    # Enable directory listing for releases/
    location /releases/ {
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;
    }

    # Cache headers for ISOs
    location ~* \.iso$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    # No caching for checksums
    location ~* (SHA256SUMS|\.asc)$ {
        expires -1;
        add_header Cache-Control "no-store";
    }
}
```

```bash
# Enable site, get TLS cert
sudo ln -s /etc/nginx/sites-available/mydistro /etc/nginx/sites-enabled/
sudo certbot --nginx -d download.mydistro.example.com
sudo systemctl reload nginx
```

### Upload via GitHub Actions release workflow

Add a deployment step to `release.yml` to sync to your VPS after the GitHub Release:

```yaml
      - name: Sync to self-hosted mirror
        if: success()
        uses: appleboy/scp-action@v0.1.7
        with:
          host: ${{ secrets.MIRROR_HOST }}
          username: ${{ secrets.MIRROR_USER }}
          key: ${{ secrets.MIRROR_SSH_KEY }}
          source: "output/*.iso,output/SHA256SUMS,output/SHA256SUMS.asc"
          target: "/var/www/mydistro/releases/${{ steps.notes.outputs.VERSION }}/"
```

---

## Step 6.2 — Torrent Seeding (Optional)

Useful when download volume grows and bandwidth becomes a cost concern.

```bash
# Install mktorrent on your server
sudo apt install mktorrent

# Create torrent files per ISO
for iso in /var/www/mydistro/releases/1.0/*.iso; do
    mktorrent \
        -a "udp://tracker.opentrackr.org:1337/announce" \
        -a "udp://tracker.torrent.eu.org:451/announce" \
        -n "$(basename $iso)" \
        -o "${iso}.torrent" \
        "$iso"
done

# Seed with qbittorrent-nox or transmission-daemon
sudo apt install transmission-daemon
# Add torrent files to transmission
```

---

## Step 6.3 — Download Page

Your website's download page should include:

```markdown
## Verify Your Download

1. Import the distro signing key:
   gpg --import distro-signing-key.asc

2. Verify the checksums file:
   gpg --verify SHA256SUMS.asc SHA256SUMS

3. Verify your ISO:
   sha256sum -c SHA256SUMS --ignore-missing
```

Provide this for every release. Users who skip it are fine, but security-conscious users will appreciate it.

---

## Part B: Ongoing Maintenance

---

## Step 6.4 — Monthly Maintenance Tasks

### Rebuild ISOs with latest packages

live-build fetches the latest package versions from Ubuntu's repos each time it runs. Rebuilding monthly means users who download get a fresher system with fewer day-1 updates.

```bash
# On a schedule (or manually trigger the CI):
git checkout dev
git commit --allow-empty -m "chore: monthly rebuild trigger"
git push origin dev
# This triggers the build-dev workflow
```

Or automate with a scheduled GitHub Actions workflow:

**`.github/workflows/scheduled-rebuild.yml`**
```yaml
name: Monthly rebuild

on:
  schedule:
    - cron: '0 2 1 * *'   # 2am on the 1st of every month
  workflow_dispatch:        # allow manual trigger

jobs:
  trigger:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4
      - name: Trigger rebuild
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git commit --allow-empty -m "chore: scheduled monthly rebuild"
          git push origin dev
```

### Review Flatpak app IDs

Flathub occasionally renames or reorganizes apps. Check monthly:

```bash
# Test that all app IDs in your install scripts still resolve
for app in org.mozilla.firefox org.libreoffice.LibreOffice com.visualstudio.code; do
    flatpak search "$app" | grep -q "$app" && echo "OK: $app" || echo "MISSING: $app"
done
```

Update `flatpak-install-desktop.sh` and `flatpak-install-developer.sh` if any IDs have changed.

### Review Ubuntu security advisories

Check [https://ubuntu.com/security/notices](https://ubuntu.com/security/notices) for anything critical affecting your base packages. Rebuilding ISOs automatically picks up fixed packages, but for active users you may want to publish a notice.

---

## Step 6.5 — Point Release Process (e.g., 1.0 → 1.1)

A point release bundles several months of package updates and any config/branding fixes.

```bash
# 1. Create a point release branch from main
git checkout main
git pull
git checkout -b release/1.1

# 2. Make any changes (updated package lists, new Flatpak apps, branding tweaks)
# ...

# 3. Update version strings
#    - common/includes.chroot/etc/os-release  (VERSION="1.1", PRETTY_NAME="MyDistro 1.1")
#    - common/includes.chroot/etc/lsb-release (DISTRIB_RELEASE=1.1)
#    - editions/*/includes.chroot/etc/calamares/branding/mydistro/branding.desc

# 4. Test locally
make desktop ARCH=amd64

# 5. Open PR: release/1.1 → main
# 6. CI must pass
# 7. Merge to main
# 8. Tag
git checkout main
git pull
git tag -a v1.1 -m "MyDistro 1.1"
git push origin v1.1
```

---

## Step 6.6 — Major Release: Rebasing on a New Ubuntu LTS

Every ~2 years Ubuntu releases a new LTS. Rebasing keeps you on supported packages.

Example: moving from Ubuntu 24.04 (noble) → 26.04 (next LTS codename, TBD).

```bash
# 1. Create a new major release branch
git checkout main
git checkout -b release/2.0

# 2. Update distro.conf — single source of truth for branding and Ubuntu base
#    Change: UBUNTU_CODENAME="noble"
#    To:     UBUNTU_CODENAME="<next-codename>"
#    Also bump: DISTRO_VERSION="2.0"
#    Then propagate changes to all docs and build configs:
./scripts/apply-branding.sh --apply

# 3. Update lb-config in all editions (if not covered by apply-branding.sh)
#    Change: --distribution noble
#    To:     --distribution <next-codename>

# 4. Update sources.list
#    Change noble → <next-codename>

# 5. Update os-release
#    VERSION="2.0"  PRETTY_NAME="ChaoticEvil 2.0"

# 6. Test build
make server ARCH=amd64
# Fix any package changes (new names, removed packages, etc.)

make desktop ARCH=amd64
make developer ARCH=amd64

# 7. Verify Calamares still works (may need config updates for new Ubuntu)

# 8. Full test pass — all three editions, both arches

# 9. PR → main → tag v2.0
```

### Keep the 1.x branch alive

After releasing 2.0, maintain the 1.x line for at least 12 months:
- Cherry-pick critical fixes from `main` → `release/1.x`
- Do monthly rebuilds on the 1.x branch to pick up Ubuntu security updates
- Clearly mark 1.x ISOs as "legacy" on the download page

---

## Step 6.7 — Components to Monitor

Set up notifications or calendar reminders for:

| Component | What to Watch | Where |
|---|---|---|
| Ubuntu LTS | EOL dates, security notices | ubuntu.com/security/notices |
| Calamares | New releases, breaking changes | github.com/calamares/calamares/releases |
| live-build | Changes in Ubuntu packaging | debian.org/devel/debian-live |
| Flathub | App ID changes, deprecated apps | flathub.org |
| XFCE | Major version releases (4.x → 5.x) | xfce.org |
| Docker CE | Package name / repo changes | docs.docker.com/engine/install/ubuntu |

---

## Step 6.8 — Issue Tracking and Community (Optional)

Once the distro is public:

- Enable GitHub Discussions for Q&A (less noise than Issues)
- Create issue templates:
  - `bug_report.md` — require edition, arch, install method, steps to reproduce
  - `flatpak_request.md` — request adding an app to the post-install list

**`.github/ISSUE_TEMPLATE/bug_report.md`**
```markdown
---
name: Bug Report
about: Report a problem with MyDistro
---

**Edition**: [ ] Server  [ ] Desktop  [ ] Developer
**Architecture**: [ ] amd64  [ ] arm64
**Version**: 
**Install method**: [ ] Fresh install  [ ] Live session

**Steps to reproduce**:
1.
2.
3.

**Expected behaviour**:

**Actual behaviour**:

**Logs** (attach `/var/log/calamares.log` or `journalctl -b` output if relevant):
```

---

## Step 6.9 — Final Pre-Release Checklist

Before publishing the first public release, verify:

- [ ] All 6 ISOs build cleanly from a clean checkout
- [ ] All 6 ISOs boot in QEMU
- [ ] Desktop and Developer installer completes (online + offline)
- [ ] Flatpak apps install correctly post-install (online)
- [ ] `os-release` shows correct distro name and version in all editions
- [ ] GRUB shows distro name and themed background
- [ ] Plymouth shows branded boot splash
- [ ] LightDM shows branded login screen
- [ ] XFCE desktop applies theme, icons, and wallpaper for new users
- [ ] SHA256SUMS and SHA256SUMS.asc generated and correct
- [ ] GPG verification of SHA256SUMS works with published `distro-signing-key.asc`
- [ ] Download page has verification instructions
- [ ] GitHub Release page lists all ISOs

---

---

## Part C: Pushing Updates to Installed Users

---

## Step 6.10 — Releasing a Branding or Config Update

ISO rebuilds deliver updates to new installs. The custom apt repo (set up in Phase 2 Step 2.5) delivers updates to **existing installs** via `apt upgrade` / `unattended-upgrades`.

Use this process any time you change wallpapers, Plymouth theme, LightDM config, Flatpak app lists, or any other ChaoticEvil-specific file.

```bash
# 1. Make your changes to the branding files in packages/chaoticevil-branding/

# 2. Bump the version in packages/chaoticevil-branding/DEBIAN/control
#    Version: 1.0.0  →  1.0.1

# 3. Commit and push — or create a GitHub Release
#    The publish-apt.yml workflow (Phase 2 Step 2.5.3) triggers automatically,
#    builds the .deb, runs reprepro, and deploys to GitHub Pages.
git add packages/chaoticevil-branding/
git commit -m "release: chaoticevil-branding 1.0.1"
git push origin main
# (or trigger via a GitHub Release, which also runs the release ISO build)
```

Existing users receive the update:
- **Automatically**: `unattended-upgrades` runs daily and applies it silently
- **Manually**: `sudo apt update && sudo apt upgrade`

> If you're using an alternative hosting backend (VPS, GCP, Cloudflare), see [Phase 2 Appendix A](../phases/PHASE2_BASE_SYSTEM.md#appendix-a--apt-repo-hosting-alternatives) for the equivalent deployment step.

### What to put in `chaoticevil-branding`

| File type | Path in package | When to update |
|---|---|---|
| Wallpaper | `usr/share/backgrounds/chaoticevil/` | New release art |
| Plymouth theme files | `usr/share/plymouth/themes/chaoticevil/` | Boot splash changes |
| LightDM greeter config | `etc/lightdm/lightdm-gtk-greeter.conf` | Login screen changes |
| XFCE defaults | `etc/skel/.config/xfce4/` | Desktop default changes |
| MOTD / login banner | `etc/motd` | Messaging changes |
| Flatpak app list | `usr/lib/chaoticevil/flatpak-apps.list` | Add/remove apps |

### What NOT to put in `chaoticevil-branding`

- Packages that are already in the Ubuntu repos — let `apt` manage those
- Binary tools or libraries — make a separate package for those
- Anything that requires a reboot to take effect without user awareness

---

## Step 6.11 — Adding or Removing Flatpak Apps for Existing Users

Flatpak apps are installed by a post-install script during the Calamares install session. New users get whatever is in the script at their install time. Existing users do **not** automatically get new apps — they only get updates to apps they already have.

To push a new Flatpak app to existing users:

**Option A — Ship a systemd oneshot service** (recommended)

Add to `chaoticevil-branding` package:

`usr/lib/systemd/system/chaoticevil-flatpak-provision.service`:
```ini
[Unit]
Description=ChaoticEvil Flatpak provisioning
ConditionPathExists=!/var/lib/chaoticevil/flatpak-provisioned-1.0.1
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/lib/chaoticevil/flatpak-provision.sh
ExecStartPost=/bin/bash -c 'mkdir -p /var/lib/chaoticevil && touch /var/lib/chaoticevil/flatpak-provisioned-1.0.1'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

The stamp file (`flatpak-provisioned-1.0.1`) ensures the service only runs once after the package update, not on every boot.

**Option B — Document it** (simpler)

Announce new apps in release notes. Users who want them run `flatpak install flathub <app-id>` manually.

---

## Maintenance Calendar Summary

| Frequency | Task |
|---|---|
| Monthly | Rebuild ISOs (picks up latest packages), review Flatpak app IDs |
| Per Ubuntu advisory | Check if advisory affects your packages; rebuild if critical |
| Per branding/config change | Bump `chaoticevil-branding` version, push to apt repo |
| Per point release (every 3–6 months) | Update version strings, PR → main → tag |
| Per Ubuntu LTS (every 2 years) | Rebase on new LTS codename, major version bump |
| Ongoing | Monitor component release pages for breaking changes |

---

## Back to Overview

→ [DISTRO_PLAN.md](../DISTRO_PLAN.md)
