# Phase 4: Installer (Debian)

**Goal**: Calamares installer works on Desktop and Developer editions — branding, language/keyboard/timezone/user/partitioning, and post-install Flatpak provisioning — with no Ubuntu helper packages.

**Prerequisite**: [Phase 2 (Debian)](PHASE2_BASE_SYSTEM.md) complete — Desktop ISO boots to XFCE.

---

## The key difference from Ubuntu

On Ubuntu, `calamares-settings-ubuntu` provides a pre-written `settings.conf`, pre-configured module configs, and working defaults. On Debian it does not exist. You write every configuration file yourself. This is more work but gives complete control over the installer flow.

All config files land in the ISO via `editions/desktop/includes.chroot/etc/calamares/`.

---

## Step 4.1 — settings.conf

`editions/desktop/includes.chroot/etc/calamares/settings.conf`:

```yaml
---
modules-search: [ local, /usr/lib/calamares/modules ]

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
    - removeuser
    - users
    - displaymanager
    - networkcfg
    - hwclock
    - grubcfg
    - bootloader
    - packages
    - shellprocess
    - umount
  - show:
    - finished

branding: chaoticevil
prompt-install: false
dont-chroot: false
```

> **Module order matters.** `partition` and `mount` must precede `unpackfs`. `users` must precede `displaymanager`. `grubcfg` must precede `bootloader`.

---

## Step 4.2 — unpackfs.conf

`editions/desktop/includes.chroot/etc/calamares/modules/unpackfs.conf`:

```yaml
---
unpack:
  - source: /run/live/medium/live/filesystem.squashfs
    sourcefs: squashfs
    destination: ""
```

Debian live-build places the squashfs at `live/filesystem.squashfs` on the ISO. At runtime it is mounted under `/run/live/medium/`.

> If the build uses a different squashfs path, boot the live ISO, run `findmnt | grep squash` to locate it, and adjust `source` accordingly.

---

## Step 4.3 — users.conf

`editions/desktop/includes.chroot/etc/calamares/modules/users.conf`:

```yaml
---
defaultGroups:
  - name: users
    state: exists
  - name: sudo
    state: must-exist
  - name: audio
    state: exists
  - name: video
    state: exists
  - name: plugdev
    state: exists
  - name: netdev
    state: exists
  - name: bluetooth
    state: exists
  - name: flatpak
    state: exists

autologinGroup: autologin
doAutologin: false

sudoersGroup: sudo
setRootPassword: false

passwordRequirements:
  minLength: 6
  maxLength: -1

userShell: /bin/bash
```

> Debian uses `sudo` group (same as Ubuntu). The `flatpak` group entry is safe to keep even if the group doesn't pre-exist — Calamares will skip `state: exists` groups that are absent.

---

## Step 4.4 — partition.conf

`editions/desktop/includes.chroot/etc/calamares/modules/partition.conf`:

```yaml
---
efiSystemPartition: /boot/efi
efiSystemPartitionSize: 512MiB
efiSystemPartitionName: EFI

initialPartitioningChoice: none
initialSwapChoice: none

defaultFileSystemType: ext4
availableFileSystemTypes:
  - ext4
  - btrfs
  - xfs

drawNestedPartitions: false
alwaysShowPartitionLabels: true
```

---

## Step 4.5 — displaymanager.conf

`editions/desktop/includes.chroot/etc/calamares/modules/displaymanager.conf`:

```yaml
---
displaymanagers:
  - lightdm

defaultDesktopEnvironment:
  executable: startxfce4
  desktopFile: xfce4.desktop

autologinUser: ""
```

---

## Step 4.6 — grubcfg.conf

`editions/desktop/includes.chroot/etc/calamares/modules/grubcfg.conf`:

```yaml
---
overwrite: false
keepDistributor: false
distributor: "ChaoticEvil"
```

---

## Step 4.7 — bootloader.conf

`editions/desktop/includes.chroot/etc/calamares/modules/bootloader.conf`:

```yaml
---
efiBootLoader: "grub"
grubInstall: "grub-install"
grubMkconfig: "update-grub"
grubCfg: "/boot/grub/grub.cfg"
grubProbe: "grub-probe"
efiBootloaderId: "debian"

installEFIFallback: false
```

> `grubMkconfig` is `update-grub` on Debian (not `grub-mkconfig -o /boot/grub/grub.cfg`).

---

## Step 4.8 — packages.conf (optional)

If you want Calamares to install or remove packages during installation (separate from the ISO's live package set), create `editions/desktop/includes.chroot/etc/calamares/modules/packages.conf`:

```yaml
---
backend: apt

operations:
  - remove:
    - calamares
    - calamares-data
    - live-boot
    - live-boot-doc
    - live-boot-initramfs-tools
    - live-config
    - live-config-systemd
    - live-tools
```

This removes live-system packages from the installed system after Calamares completes.

---

## Step 4.9 — Post-install Flatpak (shellprocess.conf)

`editions/desktop/includes.chroot/etc/calamares/modules/shellprocess.conf`:

```yaml
---
dontChroot: false
timeout: 300

script:
  - "-": |
      flatpak remote-add --system --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo
  - "-": /usr/lib/chaoticevil/flatpak-install-desktop.sh
```

The `-` prefix makes each step non-fatal — the installation continues even if Flatpak fails (e.g., no internet at install time).

Create `editions/desktop/includes.chroot/usr/lib/chaoticevil/flatpak-install-desktop.sh`:

```bash
#!/bin/bash
# Post-install Flatpak provisioning — Desktop edition
set -e

APPS=(
    org.mozilla.firefox
    org.libreoffice.LibreOffice
    org.videolan.VLC
    com.github.tchx84.Flatseal
)

for app in "${APPS[@]}"; do
    flatpak install --system --noninteractive flathub "$app" 2>/dev/null || true
done
```

```bash
chmod +x editions/desktop/includes.chroot/usr/lib/chaoticevil/flatpak-install-desktop.sh
```

Create the Developer variant at `editions/developer/includes.chroot/usr/lib/chaoticevil/flatpak-install-developer.sh` with additional apps (VS Code, etc.).

---

## Step 4.10 — Branding

Same as the Ubuntu plan. See [ubuntu/phases/PHASE3_BRANDING.md](../../ubuntu/phases/PHASE3_BRANDING.md) for `branding.desc` and asset creation.

Place assets in `editions/desktop/includes.chroot/usr/share/calamares/branding/chaoticevil/`.

The `branding.desc` file is identical to the Ubuntu version — the `componentName` field must match the `branding:` value in `settings.conf` (`chaoticevil`).

---

## Step 4.11 — Desktop launcher

`editions/desktop/includes.chroot/home/user/Desktop/install-chaoticevil.desktop`:

```ini
[Desktop Entry]
Version=1.0
Type=Application
Name=Install ChaoticEvil Linux
Comment=Install ChaoticEvil Linux to your system
Exec=pkexec calamares
Icon=calamares
Terminal=false
Categories=System;
```

> Debian's polkit handles `pkexec` — no additional `.pkla` file needed for launching Calamares.

---

## Step 4.12 — Full installation test

```bash
# Create a blank test disk
qemu-img create -f qcow2 /tmp/test-install.qcow2 25G

# Boot Desktop ISO against the blank disk
qemu-system-x86_64 \
  -m 4096 -smp 2 \
  -cdrom output/chaoticevil-1.0-desktop-amd64.iso \
  -drive file=/tmp/test-install.qcow2,format=qcow2,if=virtio \
  -boot d -enable-kvm \
  -vga virtio -display gtk
```

Walk through the full Calamares flow. After reboot into the installed system:

```bash
cat /etc/os-release          # NAME="ChaoticEvil Linux", ID_LIKE=debian
dpkg -l | grep ubuntu        # Must return nothing
dpkg -l | grep calamares     # Should return nothing (removed by packages module)
dpkg -l | grep live-boot     # Should return nothing
flatpak list                 # Should show installed apps
systemctl status lightdm     # active
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Calamares crashes on open | `settings.conf` YAML syntax error | Run `calamares -d` in terminal for verbose output |
| `unpackfs` fails | Wrong squashfs path | `findmnt \| grep squash` to locate actual path |
| Bootloader fails | `grub-efi-amd64` not installed | Add `grub-efi-amd64` to desktop package list |
| `users` module fails | `sudo` group doesn't exist | Ensure `sudo` package is in `base.list` |
| Flatpak step fails silently | No internet during install | Expected — `-` prefix makes it non-fatal |
| Display manager not set | `displaymanager.conf` wrong desktop name | Verify `startxfce4` executable exists in ISO |

---

## Checklist

- [ ] `settings.conf` — valid YAML, correct module sequence
- [ ] `unpackfs.conf` — squashfs path verified against live boot
- [ ] `users.conf` — `sudo` group present, `flatpak` group listed
- [ ] `partition.conf` — EFI partition size and filesystem types set
- [ ] `displaymanager.conf` — LightDM + XFCE4 configured
- [ ] `grubcfg.conf` — distributor set to `ChaoticEvil`
- [ ] `bootloader.conf` — `grubMkconfig: update-grub`
- [ ] `packages.conf` — live system packages removed post-install
- [ ] `shellprocess.conf` — Flatpak provisioning script runs
- [ ] `flatpak-install-desktop.sh` — executable, correct app IDs
- [ ] Calamares opens from desktop launcher without errors
- [ ] Full install completes in QEMU test
- [ ] Installed system boots to LightDM, then XFCE
- [ ] `dpkg -l | grep ubuntu` returns nothing in installed system
- [ ] Flatpak apps present after install
