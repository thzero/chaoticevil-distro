# Phase 4: Installer

**Goal**: Calamares installer works for Desktop and Developer editions. Flatpak apps install post-setup when network is available. Server edition uses a separate unattended install path.

**Prerequisite**: [Phase 3: Branding](PHASE3_BRANDING.md) complete — branded ISOs build successfully.

---

## Overview

- **Desktop** and **Developer** editions use **Calamares** (graphical installer)
- **Server** edition does not use Calamares — it uses Ubuntu's `subiquity` or a preseed/autoinstall for unattended installs
- Flatpak apps are installed via a post-install shell script run by Calamares, not baked into the ISO

---

## Step 4.1 — Calamares Base Config

Calamares config lives in `/etc/calamares/` inside the ISO. Since Desktop and Developer editions each have their own Calamares config overlay, the config path is:

```
editions/desktop/includes.chroot/etc/calamares/
editions/developer/includes.chroot/etc/calamares/
```

Most of the config is identical between the two editions — only the `shellprocess-flatpak-apps.conf` differs. Create the shared structure first, then copy and edit for each edition.

### Calamares directory layout
```
/etc/calamares/
├── settings.conf
├── branding/
│   └── mydistro/
│       ├── branding.desc
│       ├── logo.png            # same as /usr/share/pixmaps/mydistro-logo.png
│       ├── slide1.png          # installer slideshow (optional)
│       └── show.qml            # slideshow script (optional)
└── modules/
    ├── welcome.conf
    ├── locale.conf
    ├── keyboard.conf
    ├── partition.conf
    ├── users.conf
    ├── summary.conf
    ├── shellprocess-flatpak.conf
    └── shellprocess-flatpak-apps.conf
```

---

## Step 4.2 — `settings.conf`

**`editions/desktop/includes.chroot/etc/calamares/settings.conf`**
```yaml
---
modules-search: [ local, /usr/lib/calamares/modules ]

instances: []

sequence:
  - show:
    - welcome
    - locale
    - keyboard
    - partition
    - users
    - summary
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
    - shellprocess-flatpak
    - shellprocess-flatpak-apps
    - preservefiles
    - umount
  - show:
    - finished

branding: mydistro
prompt-install: false
dont-chroot: false
disable-cancel: false
disable-cancel-during-exec: true
quit-at-end: false
```

Copy this same `settings.conf` to the developer edition:
```bash
cp editions/desktop/includes.chroot/etc/calamares/settings.conf \
   editions/developer/includes.chroot/etc/calamares/settings.conf
```

---

## Step 4.3 — `branding.desc`

Create for **both** editions (identical content):

**`editions/{desktop,developer}/includes.chroot/etc/calamares/branding/mydistro/branding.desc`**
```yaml
---
componentName: mydistro

welcomeStyleCalamares: false

strings:
  productName:          "MyDistro"
  shortProductName:     "MyDistro"
  version:              "1.0"
  shortVersion:         "1.0"
  versionedName:        "MyDistro 1.0"
  shortVersionedName:   "MyDistro 1.0"
  bootloaderEntryName:  "MyDistro"
  productUrl:           "https://mydistro.example.com"
  supportUrl:           "https://mydistro.example.com/support"
  releaseNotesUrl:      "https://mydistro.example.com/notes"
  donateUrl:            ""

images:
  productLogo:          "logo.png"
  productIcon:          "logo.png"
  productWelcome:       "languages.png"

slideshow:              "show.qml"
slideshowAPI:           2

style:
  sidebarBackground:    "#1a1a2e"
  sidebarText:          "#e0e0e0"
  sidebarTextSelect:    "#ffffff"
  sidebarTextHighlight: "#4a90d9"
```

Place `logo.png` (128×128) at:
```bash
cp branding/icons/logo-128.png \
   editions/desktop/includes.chroot/etc/calamares/branding/mydistro/logo.png
cp branding/icons/logo-128.png \
   editions/developer/includes.chroot/etc/calamares/branding/mydistro/logo.png
```

### Slideshow (optional but recommended)

A minimal `show.qml` that just shows static images:

**`editions/{desktop,developer}/includes.chroot/etc/calamares/branding/mydistro/show.qml`**
```qml
import QtQuick 2.0
import calamares.slideshow 1.0

Presentation {
    id: presentation

    function nextSlide() {
        if (presentation.currentSlide < slides.length - 1)
            presentation.currentSlide++
        else
            presentation.currentSlide = 0
    }

    Timer {
        id: timer
        interval: 5000
        repeat: true
        running: true
        onTriggered: nextSlide()
    }

    Slide {
        anchors.fill: parent
        Image {
            id: background
            source: "slide1.png"
            anchors.fill: parent
            fillMode: Image.PreserveAspectFit
        }
    }
}
```

Create a simple `slide1.png` (1024×576) with your logo and tagline. Inkscape works well for this.

---

## Step 4.4 — Module Config Files

These are identical for both editions. Create in both `editions/desktop/` and `editions/developer/`:

### `modules/welcome.conf`
```yaml
---
showSupportUrl:          true
showKnownIssuesUrl:      true
showReleaseNotesUrl:     true
showDonateUrl:           false
requirements:
  requiredStorage:       8.0
  requiredRam:           1.0
  internetCheckUrl:      "https://example.com"
  check:
    - storage
    - ram
    - power
  required:
    - storage
    - ram
```

### `modules/locale.conf`
```yaml
---
region:   "America"
zone:     "New_York"
havescreen: false
```

### `modules/keyboard.conf`
```yaml
---
writeEtcDefaultKeyboard: true
```

### `modules/partition.conf`
```yaml
---
efiSystemPartition:       "/boot/efi"
efiSystemPartitionSize:   "300M"
efiSystemPartitionName:   "EFI system partition"
defaultFileSystemType:    "ext4"
availableFileSystemTypes: ["ext4", "btrfs", "xfs"]
enableLuksAutomatedPartitioning: true
allowManualPartitioning:  true
initialPartitioningChoice: "erase"
initialSwapChoice:        "suspend"
```

### `modules/users.conf`
```yaml
---
defaultGroups:
  - name: users
    state: create
  - name: audio
    state: create
  - name: video
    state: create
  - name: plugdev
    state: create
  - name: netdev
    state: create
  - name: flatpak
    state: create

autologinGroup:   autologin
sudoersGroup:     sudo

doAutologin:      false
setRootPassword:  false
doReusePassword:  true

passwordRequirements:
  nonempty: true
  minLength: 6
  maxLength: -1
  libpwquality:
    - minlen=6

allowWeakPasswords: true
```

Add Docker group to developer edition only:

**`editions/developer/includes.chroot/etc/calamares/modules/users.conf`** — add to `defaultGroups`:
```yaml
  - name: docker
    state: create
```

---

## Step 4.5 — Flatpak Shell Process Modules

### Shared: `modules/shellprocess-flatpak.conf`
(Identical for both editions — adds the Flathub remote)
```yaml
---
dontChroot: false
timeout:    120

script:
  - "-": "flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo"
```

The `-` prefix makes failure non-fatal (no network = installer still completes).

### Desktop: `modules/shellprocess-flatpak-apps.conf`
```yaml
---
dontChroot: false
timeout:    600

script:
  - "-": "/usr/lib/mydistro/flatpak-install-desktop.sh"
```

### Developer: `modules/shellprocess-flatpak-apps.conf`
```yaml
---
dontChroot: false
timeout:    900

script:
  - "-": "/usr/lib/mydistro/flatpak-install-developer.sh"
```

---

## Step 4.6 — Flatpak Install Scripts

### `editions/desktop/includes.chroot/usr/lib/mydistro/flatpak-install-desktop.sh`
```bash
#!/bin/bash
# MyDistro Desktop — post-install Flatpak provisioning
set -euo pipefail

LOG="/var/log/mydistro-flatpak-install.log"
exec > >(tee -a "$LOG") 2>&1

echo "==> MyDistro Flatpak installer starting: $(date)"

# Network check
if ! curl -sf --max-time 10 https://dl.flathub.org > /dev/null 2>&1; then
    echo "==> No network access. Skipping Flatpak installs."
    echo "==> After connecting, run: flatpak install flathub <app-id>"
    exit 0
fi

# Ensure Flathub is added
flatpak remote-add --system --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo

APPS=(
    "org.mozilla.firefox"
    "org.libreoffice.LibreOffice"
    "org.videolan.VLC"
    "com.github.tchx84.Flatseal"
    "org.gnome.FileRoller"
)

FAILED=()

for app in "${APPS[@]}"; do
    echo "==> Installing $app..."
    if flatpak install --system --noninteractive flathub "$app"; then
        echo "==> OK: $app"
    else
        echo "==> WARNING: Failed to install $app"
        FAILED+=("$app")
    fi
done

if [ ${#FAILED[@]} -gt 0 ]; then
    echo "==> The following apps failed to install:"
    printf '     %s\n' "${FAILED[@]}"
    echo "==> You can retry them manually with: flatpak install flathub <app-id>"
fi

echo "==> Flatpak install complete: $(date)"
```
```bash
chmod +x editions/desktop/includes.chroot/usr/lib/mydistro/flatpak-install-desktop.sh
```

### `editions/developer/includes.chroot/usr/lib/mydistro/flatpak-install-developer.sh`
```bash
#!/bin/bash
# MyDistro Developer — post-install Flatpak provisioning
set -euo pipefail

LOG="/var/log/mydistro-flatpak-install.log"
exec > >(tee -a "$LOG") 2>&1

echo "==> MyDistro Developer Flatpak installer starting: $(date)"

# Network check
if ! curl -sf --max-time 10 https://dl.flathub.org > /dev/null 2>&1; then
    echo "==> No network access. Skipping Flatpak installs."
    echo "==> After connecting, run: flatpak install flathub <app-id>"
    exit 0
fi

# Install desktop apps first
echo "==> Installing desktop app set..."
bash /usr/lib/mydistro/flatpak-install-desktop.sh

# Developer-specific apps
DEV_APPS=(
    "com.visualstudio.code"
    "io.podman_desktop.PodmanDesktop"
    "rest.insomnia.Insomnia"
    "io.dbeaver.DBeaverCommunity"
    "com.getpostman.Postman"
    "org.gimp.GIMP"
)

FAILED=()

for app in "${DEV_APPS[@]}"; do
    echo "==> Installing $app..."
    if flatpak install --system --noninteractive flathub "$app"; then
        echo "==> OK: $app"
    else
        echo "==> WARNING: Failed to install $app"
        FAILED+=("$app")
    fi
done

if [ ${#FAILED[@]} -gt 0 ]; then
    echo "==> The following apps failed to install:"
    printf '     %s\n' "${FAILED[@]}"
fi

echo "==> Developer Flatpak install complete: $(date)"
```
```bash
chmod +x editions/developer/includes.chroot/usr/lib/mydistro/flatpak-install-developer.sh
```

> **Important**: The developer script calls the desktop script, so the desktop script must be present in the developer edition too. Copy it:
```bash
cp editions/desktop/includes.chroot/usr/lib/mydistro/flatpak-install-desktop.sh \
   editions/developer/includes.chroot/usr/lib/mydistro/flatpak-install-desktop.sh
```

---

## Step 4.7 — Server Edition: Unattended Install (autoinstall)

The server edition uses Ubuntu's `autoinstall` (cloud-init/subiquity) rather than Calamares.

Create a sample autoinstall config that users can supply via kernel cmdline or `user-data` file:

**`editions/server/includes.chroot/usr/share/mydistro/autoinstall-example.yaml`**
```yaml
#cloud-config
autoinstall:
  version: 1
  locale: en_US.UTF-8
  keyboard:
    layout: us
  network:
    ethernets:
      eth0:
        dhcp4: true
    version: 2
  storage:
    layout:
      name: lvm
  identity:
    hostname: mydistro-server
    username: admin
    # Generate password hash: openssl passwd -6 yourpassword
    password: "$6$yourhashhere"
  ssh:
    install-server: true
    allow-pw: true
  packages:
    - htop
    - tmux
  late-commands:
    - curtin in-target -- ufw --force enable
    - curtin in-target -- ufw allow ssh
```

Document this in a README inside the server edition.

---

## Step 4.8 — Test the Installer in VirtualBox/QEMU

### Create a QEMU disk image
```bash
qemu-img create -f qcow2 /tmp/test-install.qcow2 20G
```

### Boot and install (desktop edition)
```bash
qemu-system-x86_64 \
  -m 4096 \
  -cdrom output/mydistro-1.0-desktop-amd64.iso \
  -hda /tmp/test-install.qcow2 \
  -boot d \
  -vga virtio \
  -display gtk \
  -net nic \
  -net user \
  -enable-kvm
```

### Run through the installer
1. Select language and locale
2. Select keyboard
3. Select partition scheme (use "Erase disk" for simplicity in testing)
4. Set username and password
5. Review summary and click Install
6. Watch for Flatpak install step — should run after packages step
7. Reboot into installed system

### Boot the installed system
```bash
qemu-system-x86_64 \
  -m 4096 \
  -hda /tmp/test-install.qcow2 \
  -boot c \
  -vga virtio \
  -display gtk \
  -net nic \
  -net user \
  -enable-kvm
```

### What to verify post-install
```bash
# Check Flatpak apps installed
flatpak list --system

# Check log
cat /var/log/mydistro-flatpak-install.log

# Check os-release
cat /etc/os-release

# Check GRUB entry
cat /boot/grub/grub.cfg | grep MyDistro
```

---

## Step 4.9 — Offline Install Test

```bash
# Boot without network (remove -net flags from QEMU)
qemu-system-x86_64 \
  -m 4096 \
  -cdrom output/mydistro-1.0-desktop-amd64.iso \
  -hda /tmp/test-install-offline.qcow2 \
  -boot d \
  -vga virtio \
  -display gtk
  # No -net flags = no network
```

### Verify offline install completes
- Installer should complete without errors
- Flatpak step should print "No network access" message and exit cleanly
- System should boot to desktop normally
- Log at `/var/log/mydistro-flatpak-install.log` should show the skip message

---

## Step 4.10 — Commit

```bash
git add .
git commit -m "feat: add Calamares installer config and Flatpak post-install scripts"
git push origin dev
```

---

## Checklist

- [ ] `settings.conf` created for desktop and developer editions
- [ ] `branding.desc` created for both editions
- [ ] `logo.png` placed in branding directory for both editions
- [ ] `show.qml` slideshow created (or placeholder)
- [ ] `welcome.conf` created
- [ ] `locale.conf` created
- [ ] `keyboard.conf` created
- [ ] `partition.conf` created
- [ ] `users.conf` created (developer adds docker group)
- [ ] `shellprocess-flatpak.conf` created (adds Flathub remote)
- [ ] `shellprocess-flatpak-apps.conf` created per edition (different script paths)
- [ ] `flatpak-install-desktop.sh` created and executable
- [ ] `flatpak-install-developer.sh` created and executable
- [ ] Desktop install script copied into developer edition
- [ ] Server autoinstall example created
- [ ] Desktop online install tested in QEMU — Flatpak apps install
- [ ] Desktop offline install tested in QEMU — completes cleanly, log shows skip message
- [ ] Developer online install tested — all dev Flatpaks install
- [ ] Post-install: `cat /etc/os-release` shows MyDistro
- [ ] Post-install: Flatpak list shows installed apps
- [ ] Changes committed to `dev`

---

## Next Step

→ [Phase 5: CI/CD Pipeline](PHASE5_CICD.md)
