#!/bin/bash

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

echo "WARNING: This will completely wipe $DISK."
read -p "Are you sure you want to continue? (y/N): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "Installation aborted."
    exit 1
fi

echo "=> Partitioning $DISK (UEFI)..."
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart primary ext4 513MiB 100%

if [[ "$DISK" == *"nvme"* ]]; then
    PART_BOOT="${DISK}p1"
    PART_ROOT="${DISK}p2"
else
    PART_BOOT="${DISK}1"
    PART_ROOT="${DISK}2"
fi

echo "=> Formatting partitions..."
mkfs.fat -F 32 "$PART_BOOT"
mkfs.ext4 -F "$PART_ROOT"

echo "=> Mounting partitions..."
mount "$PART_ROOT" /mnt
mkdir -p /mnt/boot/efi
mount "$PART_BOOT" /mnt/boot/efi

echo "=> Installing base system and OpenRC packages..."
basestrap /mnt base base-devel openrc elogind-openrc linux linux-firmware nano networkmanager-openrc grub efibootmgr

echo "=> Generating fstab..."
fstabgen -U /mnt >> /mnt/etc/fstab

echo "=> Configuring the system..."

cat <<EOF > /mnt/chroot-install.sh
#!/bin/bash

ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc

# Locale
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Hostname and Network (OpenRC way)
echo "$HOSTNAME" > /etc/hostname
# Enable NetworkManager in OpenRC
rc-update add NetworkManager default

# Users & Passwords
echo "root:$PASSWORD" | chpasswd
useradd -m -G wheel -s /bin/bash "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd
# Allow 'wheel' group to use sudo
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Bootloader (GRUB for UEFI)
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=grub
grub-mkconfig -o /boot/grub/grub.cfg
EOF

chmod +x /mnt/chroot-install.sh
artix-chroot /mnt /chroot-install.sh

rm /mnt/chroot-install.sh

echo "=========================================="
echo " Installation Complete! You can reboot.   "
echo "=========================================="
