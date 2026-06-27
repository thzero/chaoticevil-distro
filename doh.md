Here is the complete, streamlined guide combining everything into a single, cohesive workflow. This process uses Ubuntu Base 24.04 LTS, the latest stable Mainline Linux kernel (v6.13+), an optimized XFCE desktop, the Calamares installer with custom branding, and a modern hybrid UEFI/BIOS bootloader configuration.
Execute these steps on an existing Ubuntu or Debian host machine.
------------------------------
## Step 1: Install Build Dependencies on Your Host
Install the packages required to manipulate environments, extract assets, compress files, and generate the final ISO image.

sudo apt update
sudo apt install -y wget debootstrap mtools xorriso isolinux syslinux-common grub-pc-bin grub-efi-amd64-bin squashfs-tools

## Step 2: Set Up the Project Workspace Layout
Create an organized folder system to keep your raw operating system structures separate from your boot files.

mkdir -p ~/custom_distro/{chroot,iso/casper,iso/boot/grub}
cd ~/custom_distro

## Step 3: Fetch and Extract Ubuntu Base
Download the minimal official root filesystem payload to build upon.

# Pull down the base tarball
wget https://ubuntu.com
# Extract it using sudo to carefully preserve absolute root user file permissions
sudo tar -zxf ubuntu-base-24.04-base-amd64.tar.gz -C chroot/

## Step 4: Mount Host Interfaces & Pivot to Chroot
Bind core kernel API folders from your host into the root environment so that tasks like downloading dependencies and loading services can run seamlessly.

sudo mount --bind /dev chroot/dev
sudo mount --bind /run chroot/run
sudo mount -t proc proc chroot/proc
sudo mount -t sysfs sysfs chroot/sys
sudo mount -t devpts devpts chroot/dev/pts
sudo cp /etc/resolv.conf chroot/etc/
# Enter the virtual environment
sudo chroot chroot

------------------------------
## Step 5: Install Packages and Configuration Deployed Inside Chroot
(All commands in this step are executed inside the chroot prompt)
## 5.1 Base System Components & Lightweight GUI
Update package databases and fetch the required core layout layers. We use --no-install-recommends to keep the image minimal.

apt update && apt upgrade -y
# Core utilities and system daemons
apt install --no-install-recommends -y \
    systemd-sysv libuutil3linux network-manager network-manager-gnome sudo \
    live-boot live-config live-config-systemd binutils coreutils polkitd wget
# Graphical Server, Login Display Manager, and XFCE4 Workspace Environments
apt install --no-install-recommends -y \
    xserver-xorg xinit lightdm xfce4 xfce4-terminal mousepad
# Install Calamares Engine and its standard setup structures
apt install --no-install-recommends -y \
    calamares calamares-settings-ubuntu gparted squid-installer-dependencies

## 5.2 Fetch and Provision the Latest Mainline Linux Kernel
Pull down the latest unsigned mainline build files directly from the Ubuntu Kernel Archive.

mkdir -p /tmp/kernel && cd /tmp/kernel
# Fetch Kernel 6.13 binaries (Verify current release string modifications if needed)
wget https://ubuntu.com
wget https://ubuntu.com
# Explicitly deploy the package structures
dpkg -i *.deb
cd /

## 5.3 Configure Networking, Autologin, and Desktop Applets
Configure system initialization scripts to automate user desktop startup routines and authorize permission overrides.

# Enable the background networking service
systemctl enable NetworkManager
# Allow the desktop panels to autostart the wireless tray indicator icon
mkdir -p /etc/xdg/autostart
cp /usr/share/applications/nm-applet.desktop /etc/xdg/autostart/
# Grant the live user full networking privileges without prompting for a root password
mkdir -p /etc/polkit-1/localauthority/50-local.d/
cat <<EOF > /etc/polkit-1/localauthority/50-local.d/10-networkmanager.pkla
[Allow Live User Network Control]
Identity=unix-user:liveuser
Action=org.freedesktop.NetworkManager.*
ResultAny=yes
ResultInactive=yes
ResultActive=yes
EOF
# Direct LightDM to skip credential authentication screens and log directly into XFCE
mkdir -p /etc/lightdm/lightdm.conf.d/
cat <<EOF > /etc/lightdm/lightdm.conf.d/80-live-autologin.conf
[Seat:*]
user-session=xfce
autologin-user=liveuser
autologin-user-timeout=0
EOF

## 5.4 Customize Branding Elements for Calamares
Inject matching branding parameters directly into the configuration settings profile of your installer layout.

mkdir -p /usr/share/calamares/branding/mycustomdistro/

cat <<EOF > /usr/share/calamares/branding/mycustomdistro/branding.desc
---
componentName:   mycustomdistro
welcomeStyleCalamares: true

strings:
    productName:         "My Custom OS"
    shortProductName:    "CustomOS"
    version:             "24.04 LTS"
    shortVersion:        "24.04"
    versionedName:       "My Custom OS 24.04 LTS"
    shortVersionedName:  "CustomOS 24.04"
    bootloaderEntryName: "CustomOS"

images:
    productLogo:         "logo.png"
    productIcon:         "logo.png"
    productWelcome:      "welcome.png"

style:
    sidebarBackground:    "#2c3e50"
    sidebarText:          "#ffffff"
    sidebarTextHighlight: "#3498db"
EOF
# Force Calamares to use your new profile folder scheme
sed -i 's/branding: .*/branding: mycustomdistro/' /etc/calamares/settings.conf

(Make sure to put square logo.png and wide welcome.png image assets in /usr/share/calamares/branding/mycustomdistro/ so the graphical engine displays them properly).
## 5.5 Provision Live User Environment & Clear Cache Logs
Create a default user account, configure the installer launcher icon shortcut, and clean up temporary paths to minimize file size.

# Add user account privileges
useradd -m -s /bin/bash liveuser
passwd -d liveuser
usermod -aG sudo,adm,cdrom,plugdev liveuser
# Put the Calamares installer icon on the desktop
mkdir -p /home/liveuser/Desktop
cp /usr/share/applications/calamares.desktop /home/liveuser/Desktop/
chmod +x /home/liveuser/Desktop/calamares.desktop
chown -R liveuser:liveuser /home/liveuser/Desktop
# Erase caching layers
apt autoremove -y
apt clean
rm -rf /tmp/* /root/.bash_history
# Exit the chroot jail back to your host terminal shell
exit

------------------------------
## Step 6: Extract Boot Files and Unmount Host Directories
Back on your host machine, unmount the system API paths and copy your kernel binary structures to the ISO staging layout.

# Unmount safely
sudo umount -lf chroot/dev/pts
sudo umount -lf chroot/proc
sudo umount -lf chroot/sys
sudo umount -lf chroot/dev
sudo umount -lf chroot/run
# Move your kernel execution images to the live directory layout structures
sudo cp chroot/boot/vmlinuz-*-generic iso/casper/vmlinuz
sudo cp chroot/boot/initrd.img-*-generic iso/casper/initrd

## Step 7: Compress Your Root Operating System
Compress the finalized chroot/ environment layout tree into a dense filesystem.squashfs binary core image block.

sudo mksquashfs chroot iso/casper/filesystem.squashfs -comp xz -e boot -noappend

## Step 8: Build the GRUB Configuration Target Script
Write a unified grub.cfg boot layout profile supporting dynamic lookups on both UEFI and legacy systems.

cat <<EOF > iso/boot/grub/grub.cfg
insmod part_gpt
insmod part_msdos
insmod fat
insmod iso9660

set default=0
set timeout=5

menuentry "Boot My Custom Minimal Linux (Live UEFI/BIOS)" {
    search --no-floppy --set=root --file /casper/vmlinuz
    linux /casper/vmlinuz boot=casper quiet splash ---
    initrd /casper/initrd
}
EOF

## Step 9: Package the Final Hybrid UEFI-Ready ISO File
Run xorriso on your host machine to parse your iso/ configurations, generate an EFI System Partition structure, and wrap everything up into a hybrid image.

sudo xorriso -as mkisofs \
   -iso-level 3 -full-iso9660-filenames \
   -volid "CUSTOM_OS" \
   -eltorito-boot boot/grub/bios.img \
   -no-emul-boot -boot-load-size 4 -boot-info-table \
   --eltorito-catalog boot/grub/boot.cat \
   -eltorito-alt-boot \
   -e boot/grub/efi.img \
   -no-emul-boot \
   -isohybrid-voffset 0 \
   -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
   -output my-custom-distro-uefi.iso \
   iso/

Your bootable file my-custom-distro-uefi.iso is ready in your folder. You can test it by running it in a virtual machine environment (like VirtualBox or QEMU) or flashing it to a real USB thumb drive using a tool like Rufus or dd.