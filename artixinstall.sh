#!/bin/bash
set -e

echo "=========================================="
echo " Welcome to artixinstall (OpenRC Edition) "
echo "=========================================="
echo

lsblk
echo
read -p "Enter target disk (e.g., /dev/sda or /dev/vda): " DISK
read -p "Enter hostname for the system: " HOSTNAME
read -p "Enter username for the new user: " USERNAME
read -s -p "Enter password for root and $USERNAME: " PASSWORD
echo -e "\n"
read -p "Enter Timezone (e.g., America/New_York, Europe/London) [Press Enter for UTC]: " TIMEZONE
TIMEZONE=${TIMEZONE:-UTC}
echo

read -p "Are you sure you want to continue? (y/N): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    exit 1
fi

echo "=> Partitioning $DISK..."
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart primary 1MiB 3MiB
parted -s "$DISK" set 1 bios_grub on
parted -s "$DISK" mkpart ESP fat32 3MiB 515MiB
parted -s "$DISK" set 2 esp on
parted -s "$DISK" mkpart primary ext4 515MiB 100%

if [[ "$DISK" == *"nvme"* ]]; then
    PART_BOOT="${DISK}p2"
    PART_ROOT="${DISK}p3"
else
    PART_BOOT="${DISK}2"
    PART_ROOT="${DISK}3"
fi

echo "=> Formatting partitions..."
mkfs.fat -F 32 "$PART_BOOT"
mkfs.ext4 -F "$PART_ROOT"

echo "=> Mounting partitions..."
mount "$PART_ROOT" /mnt
mkdir -p /mnt/boot/efi
mount "$PART_BOOT" /mnt/boot/efi

echo "=> Installing base system..."
basestrap /mnt base base-devel openrc elogind-openrc linux linux-firmware nano grub efibootmgr

echo "=> Generating fstab..."
fstabgen -U /mnt >> /mnt/etc/fstab

echo "=> Configuring the system..."
cat <<EOF > /mnt/chroot-install.sh
#!/bin/bash
set -e

echo "=> Enabling universe repository..."
sed -i '/\[universe\]/,/Include/s/^#//' /etc/pacman.conf
pacman -Sy

echo "=> Setting timezone to $TIMEZONE..."
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "$HOSTNAME" > /etc/hostname

echo "root:${PASSWORD}" | chpasswd
useradd -m -G wheel,video,audio -s /bin/bash "$USERNAME"
echo "${USERNAME}:${PASSWORD}" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

echo "=> Installing Xorg, Cinnamon, LightDM, and Utilities..."
pacman -S --noconfirm xorg-server cinnamon lightdm lightdm-gtk-greeter lightdm-openrc \
    dbus-openrc gnome-terminal firefox networkmanager networkmanager-openrc \
    network-manager-applet virtualbox-guest-utils

echo "=> Enabling OpenRC services..."
rc-update add NetworkManager default
rc-update add dbus default
rc-update add lightdm default

if [ -f /etc/init.d/vboxservice ]; then
    rc-update add vboxservice default
fi

echo "=> Installing GRUB..."
if [ -d /sys/firmware/efi ]; then
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=grub
else
    grub-install --target=i386-pc "$DISK"
fi
grub-mkconfig -o /boot/grub/grub.cfg
EOF

# exe chroot script
chmod +x /mnt/chroot-install.sh
artix-chroot /mnt /chroot-install.sh

rm /mnt/chroot-install.sh

echo "=========================================="
echo " Installation Complete! You can reboot.   "
echo "=========================================="
