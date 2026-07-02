# Phase 3: Branding

**Goal**: The distro has consistent visual identity across the boot splash, login screen, desktop, and system metadata.

**Prerequisite**: [Phase 2: Base System](PHASE2_BASE_SYSTEM.md) complete — all editions build with correct packages.

---

## Asset Checklist (Create These First)

Before writing any config files, prepare your source assets. All originals should be SVG stored in `branding/sources/`.

| Asset | Resolution | Format | Purpose |
|---|---|---|---|
| `logo.svg` | — | SVG | Master logo — export all others from this |
| `logo-32.png` | 32×32 | PNG | Window icons, small contexts |
| `logo-64.png` | 64×64 | PNG | App menu, medium contexts |
| `logo-128.png` | 128×128 | PNG | About dialogs |
| `logo-256.png` | 256×256 | PNG | HiDPI contexts |
| `wallpaper.png` | 1920×1080 | PNG | Default wallpaper |
| `wallpaper-hidpi.png` | 3840×2160 | PNG | HiDPI/4K screens |
| `grub-background.png` | 1920×1080 | PNG | GRUB boot menu background |
| `plymouth-logo.png` | 256×256 | PNG | Boot splash logo |

### Export PNGs from SVG using Inkscape CLI
```bash
# Install Inkscape
sudo apt install inkscape

cd branding/sources/

for size in 32 64 128 256; do
    inkscape logo.svg \
        --export-png="../icons/logo-${size}.png" \
        --export-width=$size \
        --export-height=$size
done

inkscape logo.svg \
    --export-png="../wallpaper/plymouth-logo.png" \
    --export-width=256 \
    --export-height=256
```

---

## Step 3.1 — os-release and System Identity

### `common/includes.chroot/etc/os-release`
Already created in Phase 1 — verify it contains:
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

### `common/includes.chroot/etc/lsb-release`
```ini
DISTRIB_ID=MyDistro
DISTRIB_RELEASE=1.0
DISTRIB_CODENAME=orbital
DISTRIB_DESCRIPTION="MyDistro 1.0"
```

### Logo icon for About dialogs
Place `logo-128.png` at:
```
common/includes.chroot/usr/share/pixmaps/mydistro-logo.png
common/includes.chroot/usr/share/icons/hicolor/128x128/apps/mydistro-logo.png
common/includes.chroot/usr/share/icons/hicolor/64x64/apps/mydistro-logo.png
common/includes.chroot/usr/share/icons/hicolor/32x32/apps/mydistro-logo.png
```

---

## Step 3.2 — GRUB Bootloader Theme

### Directory structure
```
common/includes.chroot/boot/grub/themes/mydistro/
├── theme.txt
├── background.png        # copy from branding/grub/
└── fonts/
    └── unicode.pf2       # copy from /usr/share/grub/
```

### `theme.txt`
```
# MyDistro GRUB2 Theme

desktop-image: "background.png"
desktop-color: "#1a1a2e"

# Title bar
title-text: ""

# Boot menu
+ boot_menu {
    left = 25%
    top = 30%
    width = 50%
    height = 35%
    item-font = "Noto Sans Regular 14"
    item-color = "#cccccc"
    selected-item-color = "#ffffff"
    selected-item-pixmap-style = "select_e"
    item-height = 32
    item-padding = 8
    item-spacing = 4
    scrollbar = false
}

# Countdown timer
+ label {
    top = 85%
    left = 0
    width = 100%
    align = "center"
    color = "#888888"
    font = "Noto Sans Regular 12"
    text = "@TIMEOUT_NOTIFICATION_MIDDLE@"
}
```

### `common/includes.chroot/etc/default/grub`
```bash
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="MyDistro"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
GRUB_CMDLINE_LINUX=""
GRUB_THEME="/boot/grub/themes/mydistro/theme.txt"
GRUB_BACKGROUND="/boot/grub/themes/mydistro/background.png"
GRUB_GFXMODE="1920x1080,auto"
GRUB_GFXPAYLOAD_LINUX="keep"
```

### Hook to copy the GRUB unicode font
Create `common/hooks/base/02-grub-theme.hook.chroot`:
```bash
#!/bin/bash
set -e

# Copy the unicode font needed by the GRUB theme
mkdir -p /boot/grub/themes/mydistro/fonts
cp /usr/share/grub/unicode.pf2 /boot/grub/themes/mydistro/fonts/ 2>/dev/null || true

update-grub 2>/dev/null || true
```
```bash
chmod +x common/hooks/base/02-grub-theme.hook.chroot
```

---

## Step 3.3 — Plymouth Boot Splash

### Directory structure
```
common/includes.chroot/usr/share/plymouth/themes/mydistro/
├── mydistro.plymouth
├── mydistro.script
└── logo.png              # copy from branding/
```

### `mydistro.plymouth`
```ini
[Plymouth Theme]
Name=MyDistro
Description=MyDistro boot splash
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/mydistro
ScriptFile=/usr/share/plymouth/themes/mydistro/mydistro.script
```

### `mydistro.script`
```
# MyDistro Plymouth script
# Simple centered logo + progress bar

logo_image = Image("logo.png");
screen_width = Window.GetWidth();
screen_height = Window.GetHeight();

logo_sprite = Sprite();
logo_sprite.SetImage(logo_image);
logo_sprite.SetX(screen_width / 2 - logo_image.GetWidth() / 2);
logo_sprite.SetY(screen_height / 2 - logo_image.GetHeight() / 2 - 50);
logo_sprite.SetZ(1);

# Background
Window.SetBackgroundTopColor(0.10, 0.10, 0.18);
Window.SetBackgroundBottomColor(0.10, 0.10, 0.18);

# Progress bar
progress_box_image = Image.FindSuitableForSize("progress_box.png", 220, 18);
progress_box_sprite = Sprite(progress_box_image);
progress_box_sprite.SetX(screen_width / 2 - progress_box_image.GetWidth() / 2);
progress_box_sprite.SetY(screen_height / 2 + 80);

progress_sprite = Sprite();
progress_sprite.SetX(screen_width / 2 - progress_box_image.GetWidth() / 2 + 1);
progress_sprite.SetY(screen_height / 2 + 81);

fun progress_callback(duration, progress) {
    bar_width = Math.Int((progress_box_image.GetWidth() - 2) * progress);
    if (bar_width < 1) { bar_width = 1; }
    bar_image = Image(bar_width, 16);
    bar_image.Scale(bar_image, bar_width, 16);
    progress_sprite.SetImage(bar_image);
    progress_sprite.SetOpacity(1);
}

Plymouth.SetBootProgressFunction(progress_callback);
```

> This script requires `progress_box.png` — create a simple 220×18 PNG with a border. For a minimal working theme, you can remove the progress bar section and just show the logo.

### Hook to register the Plymouth theme

Create `common/hooks/base/03-plymouth-theme.hook.chroot`:
```bash
#!/bin/bash
set -e

# Install our custom theme
update-alternatives --install \
    /usr/share/plymouth/themes/default.plymouth \
    default.plymouth \
    /usr/share/plymouth/themes/mydistro/mydistro.plymouth \
    100

# Set it as active
update-alternatives --set default.plymouth \
    /usr/share/plymouth/themes/mydistro/mydistro.plymouth

# Rebuild initramfs to include the theme
update-initramfs -u 2>/dev/null || true
```
```bash
chmod +x common/hooks/base/03-plymouth-theme.hook.chroot
```

---

## Step 3.4 — COSMIC Greeter (Login Screen)

COSMIC uses **greetd** as the display manager with **cosmic-greeter** as the greeter UI. The wallpaper shown on the greeter is controlled by the same backgrounds system as the desktop.

### greetd autologin config for live session

`common/includes.chroot/etc/greetd/config.toml`:
```toml
[terminal]
vt = 1

[default_session]
command = "cosmic-greeter"
user = "greeter"
```

> The `greeter` system user is created by the `01-desktop-setup.hook.chroot` from Phase 2.

### COSMIC greeter background

COSMIC greeter picks up the same wallpaper set for the desktop. Place your wallpaper at:
```
common/includes.chroot/usr/share/backgrounds/mydistro/wallpaper.png
```

The greeter reads the system-wide COSMIC background config. Seed it for all users via skel (see Step 3.5).

---

## Step 3.5 — COSMIC Theme and Desktop Defaults

COSMIC stores its configuration in RON format (Rust Object Notation) files under `~/.config/cosmic/`. System-wide defaults are seeded via `/etc/skel/.config/cosmic/` so every new user starts with your branded settings.

### COSMIC config directory structure
```
common/includes.chroot/etc/skel/.config/cosmic/
├── com.system76.CosmicBackground/v1/
│   └── state                    # wallpaper path
├── com.system76.CosmicTheme.Dark/v1/
│   └── state                    # accent color + palette
├── com.system76.CosmicTheme.Light/v1/
│   └── state
└── com.system76.CosmicSettings/v1/
    └── state                    # dark mode preference
```

### Background config
`common/includes.chroot/etc/skel/.config/cosmic/com.system76.CosmicBackground/v1/state`:
```ron
(version: 1, entries: [(output: "all", source: File("/usr/share/backgrounds/mydistro/wallpaper.png"), filter: Zoom, rotation_frequency: 0)])
```

### Dark theme + accent color
`common/includes.chroot/etc/skel/.config/cosmic/com.system76.CosmicTheme.Dark/v1/state`:
```ron
(theme: (
    name: "ChaoticEvil",
    background: (base: (0.1, 0.1, 0.18, 1.0), component: (0.13, 0.13, 0.2, 1.0), divider: (0.2, 0.2, 0.3, 1.0), on: (0.87, 0.87, 0.87, 1.0)),
    primary: (base: (0.16, 0.13, 0.24, 1.0), component: (0.19, 0.16, 0.27, 1.0), divider: (0.25, 0.22, 0.34, 1.0), on: (0.87, 0.87, 0.87, 1.0)),
    secondary: (base: (0.22, 0.22, 0.38, 1.0), component: (0.25, 0.25, 0.4, 1.0), divider: (0.3, 0.3, 0.45, 1.0), on: (0.87, 0.87, 0.87, 1.0)),
    accent: (0.29, 0.56, 0.85, 1.0),
    success: (0.27, 0.73, 0.35, 1.0),
    warning: (0.93, 0.69, 0.13, 1.0),
    destructive: (0.9, 0.3, 0.3, 1.0),
    is_dark: true,
))
```

> The `accent` value `(0.29, 0.56, 0.85, 1.0)` is `#4a90d9` in RGBA float form — matches `COLOR_ACCENT` in `distro.conf`.

### Dark mode preference
`common/includes.chroot/etc/skel/.config/cosmic/com.system76.CosmicSettings/v1/state`:
```ron
(version: 1, color_scheme: Dark)
```

### Hook to propagate skel to existing live session user

Create `common/hooks/base/04-cosmic-defaults.hook.chroot`:
```bash
#!/bin/bash
set -e

# Ensure skel cosmic config dir exists
mkdir -p /etc/skel/.config/cosmic

# The live session user is created at boot time from skel,
# so no further action needed here. The hook just validates the skel tree.
find /etc/skel/.config/cosmic -type f | sort
```
```bash
chmod +x common/hooks/base/04-cosmic-defaults.hook.chroot
```

---

## Step 3.6 — Seed COSMIC Defaults via skel

COSMIC config is per-user. Seeds land in `/etc/skel/` so every new user account (including the Calamares-created install user) starts with branded defaults.

The `state` files were written in Step 3.5. This step just validates the skel tree and copies it for the live session user (who is also seeded from skel at live-boot time).

Directory as it should exist:
```
common/includes.chroot/etc/skel/.config/cosmic/
├── com.system76.CosmicBackground/v1/state
├── com.system76.CosmicTheme.Dark/v1/state
├── com.system76.CosmicTheme.Light/v1/state
└── com.system76.CosmicSettings/v1/state
```

---

## Step 3.7 — Wallpaper Files

Copy your wallpaper files into the overlay:
```bash
cp branding/wallpaper/wallpaper.png \
   common/includes.chroot/usr/share/backgrounds/mydistro/wallpaper.png

cp branding/wallpaper/wallpaper-hidpi.png \
   common/includes.chroot/usr/share/backgrounds/mydistro/wallpaper-hidpi.png
```

---

## Step 3.8 — Build and Visually Verify

```bash
make desktop ARCH=amd64
```

Boot in QEMU with display:
```bash
qemu-system-x86_64 \
  -m 4096 \
  -cdrom output/mydistro-1.0-desktop-amd64.iso \
  -boot d \
  -vga virtio \
  -display gtk \
  -enable-kvm      # Remove if KVM not available
```

### Visual checklist
- [ ] GRUB menu shows custom background and theme
- [ ] Plymouth shows logo during boot
- [ ] COSMIC greeter shows branded wallpaper and logo
- [ ] After login: COSMIC desktop shows branded wallpaper
- [ ] Accent color matches `#4a90d9` (check System Settings → Appearance)
- [ ] Dark mode is active by default
- [ ] Panel is configured (cosmic-panel)
- [ ] `cat /etc/os-release` shows ChaoticEvil
- [ ] `pactl info` confirms PipeWire is the audio server

---

## Step 3.9 — Commit

```bash
git add .
git commit -m "feat: add branding (GRUB, Plymouth, COSMIC greeter, COSMIC theme and defaults)"
git push origin dev
```

---

## Checklist

- [ ] All source assets created (SVG logo, wallpapers, GRUB background, Plymouth logo)
- [ ] `os-release` and `lsb-release` set to distro identity
- [ ] Logo PNGs placed in `/usr/share/pixmaps/` and `/usr/share/icons/hicolor/`
- [ ] GRUB theme created and `theme.txt` written
- [ ] `/etc/default/grub` updated with theme path and distributor name
- [ ] GRUB hook created and executable
- [ ] Plymouth theme script and `.plymouth` file created
- [ ] Plymouth registration hook created and executable
- [ ] COSMIC greeter config written (`/etc/greetd/config.toml` pointing to `cosmic-greeter`)
- [ ] COSMIC background RON config seeded in `/etc/skel/.config/cosmic/`
- [ ] COSMIC dark theme RON config with accent `#4a90d9` seeded in skel
- [ ] `04-cosmic-defaults.hook.chroot` created and executable
- [ ] XFCE perchannel-xml defaults created (xsettings, desktop, xfwm4, panel)
- [ ] Skel populated with XFCE defaults
- [ ] XFCE defaults hook created and executable
- [ ] Desktop ISO builds and passes visual checklist in QEMU
- [ ] Changes committed to `dev`

---

## Next Step

→ [Phase 4: Installer](PHASE4_INSTALLER.md)
