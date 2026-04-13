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

## Step 3.4 — LightDM Login Screen

### `common/includes.chroot/etc/lightdm/lightdm-gtk-greeter.conf`
```ini
[greeter]
background=/usr/share/backgrounds/mydistro/wallpaper.png
theme-name=MyDistro
icon-theme-name=MyDistro
font-name=Noto Sans 11
xft-antialias=true
xft-hintstyle=slight
logo=/usr/share/pixmaps/mydistro-logo.png
indicators=~host;~spacer;~clock;~spacer;~session;~language;~a11y;~power
clock-format=%A, %B %e  %H:%M
user-background=false
hide-user-image=false
```

---

## Step 3.5 — XFCE Theme

### GTK + Window Manager Theme

Create the theme directory in your repo and copy it into the chroot overlay:
```
common/includes.chroot/usr/share/themes/MyDistro/
├── gtk-2.0/
│   └── gtkrc
├── gtk-3.0/
│   ├── gtk.css
│   └── gtk-dark.css (optional)
└── xfwm4/
    ├── themerc
    └── (button PNG images)
```

#### Strategy: inherit Greybird, override colors

Rather than building from zero, inherit the Greybird theme (Xubuntu default) and override your brand colors.

**`gtk-3.0/gtk.css`**
```css
/* Import Greybird as base */
@import url("/usr/share/themes/Greybird/gtk-3.0/gtk.css");

/* Override brand colors */
@define-color theme_bg_color #1a1a2e;
@define-color theme_fg_color #e0e0e0;
@define-color theme_selected_bg_color #4a90d9;
@define-color theme_selected_fg_color #ffffff;
@define-color theme_base_color #16213e;
@define-color theme_text_color #e0e0e0;
@define-color theme_button_bg_color #2a2a4a;
```

**`xfwm4/themerc`**
```ini
# Inherit from Greybird, override accent color
active_border_color=#4a90d9
active_text_color=#ffffff
active_mid_color=#2a2a4a
inactive_border_color=#333333
inactive_text_color=#888888
inactive_mid_color=#222222
title_font=Noto Sans Bold 10
```

#### Install Greybird as build dependency
Add to `editions/desktop/package-lists/desktop.list` and `editions/developer/package-lists/developer.list`:
```
greybird-gtk-theme
```

### Icon Theme

For a simple branded icon theme that inherits from an existing one, create:

```
common/includes.chroot/usr/share/icons/MyDistro/
└── index.theme
```

**`index.theme`**
```ini
[Icon Theme]
Name=MyDistro
Comment=MyDistro Icon Theme
Inherits=Papirus,hicolor
Directories=

[scalable/apps]
Size=48
MinSize=8
MaxSize=512
Type=Scalable
Context=Applications
```

Add to package lists:
```
papirus-icon-theme
```

### XFCE Default Settings

Create the XFCE configuration defaults. These are XML files in perchannel-xml format.

**`common/includes.chroot/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml`**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="MyDistro"/>
    <property name="IconThemeName" type="string" value="MyDistro"/>
    <property name="EnableEventSounds" type="bool" value="false"/>
  </property>
  <property name="Xft" type="empty">
    <property name="DPI" type="int" value="-1"/>
    <property name="Antialias" type="int" value="1"/>
    <property name="Hinting" type="int" value="1"/>
    <property name="HintStyle" type="string" value="hintslight"/>
    <property name="RGBA" type="string" value="rgb"/>
  </property>
</channel>
```

**`common/includes.chroot/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml`**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitorVirtual-1" type="empty">
        <property name="workspace0" type="empty">
          <property name="last-image" type="string"
            value="/usr/share/backgrounds/mydistro/wallpaper.png"/>
          <property name="image-style" type="int" value="5"/>
        </property>
      </property>
    </property>
  </property>
</channel>
```

**`common/includes.chroot/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml`**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="MyDistro"/>
    <property name="title_font" type="string" value="Noto Sans Bold 10"/>
    <property name="button_layout" type="string" value="O|HMC"/>
  </property>
</channel>
```

**`common/includes.chroot/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml`**

This controls the panel layout. Start with a taskbar-style layout:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-panel" version="1.0">
  <property name="configver" type="int" value="2"/>
  <property name="panels" type="array">
    <value type="int" value="1"/>
  </property>
  <property name="panel-1" type="empty">
    <property name="position" type="string" value="p=6;x=0;y=0"/>
    <property name="length" type="uint" value="100"/>
    <property name="position-locked" type="bool" value="true"/>
    <property name="size" type="uint" value="30"/>
    <property name="plugin-ids" type="array">
      <value type="int" value="1"/>
      <value type="int" value="2"/>
      <value type="int" value="3"/>
      <value type="int" value="4"/>
      <value type="int" value="5"/>
      <value type="int" value="6"/>
    </property>
  </property>
  <property name="plugins" type="empty">
    <property name="plugin-1" type="string" value="whiskermenu"/>
    <property name="plugin-2" type="string" value="separator"/>
    <property name="plugin-3" type="string" value="tasklist"/>
    <property name="plugin-4" type="string" value="separator">
      <property name="expand" type="bool" value="true"/>
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-5" type="string" value="systray"/>
    <property name="plugin-6" type="string" value="clock"/>
  </property>
</channel>
```

---

## Step 3.6 — Apply Defaults for New Users (skel)

Settings in `/etc/xdg/` are system-wide defaults, but XFCE also reads from `~/.config/xfce4/`. Use skel to seed defaults for new user accounts:

```
common/includes.chroot/etc/skel/.config/xfce4/
├── xfconf/xfce-perchannel-xml/
│   ├── xsettings.xml        (copy from /etc/xdg/xfce4/xfconf/...)
│   ├── xfce4-desktop.xml
│   └── xfwm4.xml
└── panel/
    └── (panel config, if needed beyond xfce4-panel.xml)
```

Create a hook to copy these for the live session user too:

**`common/hooks/base/04-xfce-defaults.hook.chroot`**
```bash
#!/bin/bash
set -e

# Ensure live user inherits branded defaults
# The actual live user is created at boot, so skel handles it
# Just ensure xdg dirs exist
mkdir -p /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml

cp /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/*.xml \
   /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/ 2>/dev/null || true

# Update icon cache
gtk-update-icon-cache -f /usr/share/icons/MyDistro/ 2>/dev/null || true
gtk-update-icon-cache -f /usr/share/icons/hicolor/ 2>/dev/null || true
```
```bash
chmod +x common/hooks/base/04-xfce-defaults.hook.chroot
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
- [ ] Plymouth shows logo during boot (may be brief — add `plymouth.debug` to kernel cmdline to slow it down)
- [ ] LightDM shows branded wallpaper and logo
- [ ] After login: XFCE desktop shows branded wallpaper
- [ ] Window decorations use MyDistro theme colors
- [ ] Icons use MyDistro icon theme (inheriting Papirus)
- [ ] Panel is configured correctly (app menu, taskbar, clock)
- [ ] `cat /etc/os-release` shows MyDistro

---

## Step 3.9 — Commit

```bash
git add .
git commit -m "feat: add branding (GRUB, Plymouth, LightDM, XFCE theme and defaults)"
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
- [ ] LightDM greeter config written with branded wallpaper and logo
- [ ] GTK theme created (inheriting Greybird)
- [ ] Icon theme created (inheriting Papirus)
- [ ] XFCE perchannel-xml defaults created (xsettings, desktop, xfwm4, panel)
- [ ] Skel populated with XFCE defaults
- [ ] XFCE defaults hook created and executable
- [ ] Desktop ISO builds and passes visual checklist in QEMU
- [ ] Changes committed to `dev`

---

## Next Step

→ [Phase 4: Installer](PHASE4_INSTALLER.md)
