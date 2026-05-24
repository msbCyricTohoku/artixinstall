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

read -p "Are you sure you want to continue? (y/N): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    exit 1
fi

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

mkfs.fat -F 32 "$PART_BOOT"
mkfs.ext4 -F "$PART_ROOT"

mount "$PART_ROOT" /mnt
mkdir -p /mnt/boot/efi
mount "$PART_BOOT" /mnt/boot/efi

basestrap /mnt base base-devel openrc elogind-openrc linux linux-firmware nano networkmanager-openrc grub efibootmgr

fstabgen -U /mnt >> /mnt/etc/fstab

cat <<EOF > /mnt/chroot-install.sh
#!/bin/bash
set -e

ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc

echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "$HOSTNAME" > /etc/hostname
rc-update add NetworkManager default

echo "root:${PASSWORD}" | chpasswd
useradd -m -G wheel -s /bin/bash "$USERNAME"
echo "${USERNAME}:${PASSWORD}" | chpasswd

sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

if [ -d /sys/firmware/efi ]; then
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=grub
else
    grub-install --target=i386-pc "$DISK"
fi
grub-mkconfig -o /boot/grub/grub.cfg
EOF

chmod +x /mnt/chroot-install.sh
artix-chroot /mnt /chroot-install.sh

rm /mnt/chroot-install.sh

echo "=========================================="
echo " Installation Complete! You can reboot.   "
echo "=========================================="
