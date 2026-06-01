
#!/usr/bin/env bash
# ╔══════════════════════════════════════╗
# ║   archinstall-script-netix           ║
# ║   curl -s https://... | bash         ║
# ╚══════════════════════════════════════╝
set -e

# ── USER CONFIG (edit these) ────────────

# ── DISK PICKER ─────────────────────────
echo ""
echo "Available disks:"
echo ""
lsblk -d -o NAME,SIZE,MODEL | grep -v "loop"
echo ""

# List only real disks (no partitions, no loops)
mapfile -t DISKS < <(lsblk -d -n -o NAME | grep -v loop)

select PICK in "${DISKS[@]}"; do
  [[ -n "$PICK" ]] && DISK="/dev/$PICK" && break
  echo "Invalid choice, try again."
done </dev/tty

echo ""
echo "  Installing to: $DISK"
echo "  ALL DATA ON $DISK WILL BE DESTROYED."
echo ""
read -rp "  Type YES to confirm: " CONFIRM </dev/tty
[[ "$CONFIRM" != "YES" ]] && echo "Aborted." && exit 1

# ── USER SETUP ──────────────────────────
echo ""
read -rp "  Hostname: " HOSTNAME </dev/tty
read -rp "  Username: " USERNAME </dev/tty

while true; do
  read -rsp "  Password: " PASSWORD </dev/tty; echo ""
  read -rsp "  Confirm password: " PASSWORD2 </dev/tty; echo ""
  [[ "$PASSWORD" == "$PASSWORD2" ]] && break
  echo "  Passwords don't match, try again."
done

TIMEZONE="Europe/Bucharest"
LOCALE="en_US.UTF-8"

PKGS="xorg xorg-xinit xorg-xrandr libx11 libxft libxinerama \
      firefox flameshot htop pipewire pipewire-pulse ttf-hack \
      ttf-jetbrains-mono noto-fonts-emoji"
# ────────────────────────────────────────

echo "==> Setting up mirrors"
reflector --country Romania --latest 5 --save /etc/pacman.d/mirrorlist
sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf

echo "==> Partitioning $DISK"
parted -s "$DISK" mklabel gpt \
  mkpart ESP fat32 1MiB 513MiB set 1 esp on \
  mkpart root ext4 513MiB 100%
mkfs.fat -F32 "${DISK}1"
mkfs.ext4 -F "${DISK}2"
mount "${DISK}2" /mnt
mkdir -p /mnt/boot/efi
mount "${DISK}1" /mnt/boot/efi

echo "==> Installing base"
pacstrap /mnt base base-devel linux linux-firmware networkmanager \
              grub efibootmgr git curl

genfstab -U /mnt >> /mnt/etc/fstab

echo "==> Entering chroot"
arch-chroot /mnt /bin/bash <<CHROOT
set -e

# Locale & time
ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc
echo "${LOCALE} UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf
echo "${HOSTNAME}" > /etc/hostname
cat >> /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

# Pacman parallel downloads inside chroot too
sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf

# Bootloader
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# User
useradd -m -G wheel,audio,video -s /bin/bash "${USERNAME}"
echo "${USERNAME}:${PASSWORD}" | chpasswd
echo "root:${PASSWORD}" | chpasswd
echo "%wheel ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Packages
pacman -S --noconfirm --needed ${PKGS}

# Enable services
systemctl enable NetworkManager

# DWM from GitHub
sudo -u ${USERNAME} bash <<USEREOF
cd /home/${USERNAME}
git clone https://github.com/mel0nze/DWM-Netix.git dwm
cd dwm && make && sudo make clean install && cd

git clone https://github.com/mel0nze/St-Netix.git st
cd st && make && sudo make clean install && cd ..

git clone https://github.com/mel0nze/Dmenu-Netix.git dmenu
cd dmenu && make && sudo make clean install && cd ..

echo "exec dwm" > /home/${USERNAME}/.xinitrc
USEREOF

CHROOT

echo ""
echo "══════════════════════════════════"
echo "  Done. Remove ISO and reboot."
echo "══════════════════════════════════"
