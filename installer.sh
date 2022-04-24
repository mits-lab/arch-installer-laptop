#!/usr/bin/bash

## Monocle IT Solutions Labs ##
## Server Baseline - Arch Linux Installation Script ##
## installer.sh
## Rev. 2022041219 ##

# Tested on Archlinux 2022 x86_64 (archlinux-2022.03.01-x86_64.iso)
#
# !!! CONNECT TO THE INTERNET BEFORE EXECUTING THIS SCRIPT !!!
#
# The installation is comprised of two scripts
# Script should be executed from the arch liveCD terminal as the root user.
# Adjust data storage device as needed.
# Script cleans and sets up the disk with dmcrypt and LVM partitions

# The MIT License (MIT)
# 
# Copyright (c) 2022 Monocle IT Solutions/installer.sh
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#

# hostname format is host.example.com
# standard alpha numeric user name
# password should include letter numbers and special character

red='\e[0;31m'
cyan='\e[0;36m'
normal='\e[0m' # No Color

clear

echo -n -e "\nMITS - Arch Baseline System Bootstrap Utility\n"
echo -n -e "$cyan--------------------------------------------- $normal\n\n"

echo -n -e "Enter the system hostname in the following format\n"
echo -n -e " \n$cyan host.example.com$normal\n\n"
echo -n -e "hostname: "
read _hostname
echo -n -e "\n"
echo -n -e "Your hostname is$cyan $_hostname $normal\n\n"

echo -n -e "Enter a root password..\n"
echo -n -e "root password: "
read -s _rootpass
echo -n -e "\n\n"

echo -n -e "Enter a password to unlock the system partition at boot..\n"
echo -n -e "password: "
read -s _bootpass
echo -n -e "\n"

#_hostname=
#_rootpass=
#_bootpass=

### Vars of note

bold=`tput bold`
normal=`tput sgr0`

_host=$(echo "$HOSTNAME" | cut -d. -f1)
_domain=$(echo "$HOSTNAME" | cut -f2-3 -d.)
_ipaddress=$(curl -s https://ipinfo.io/ip)
_urltest=google.ca
_localscriptdir=/root/
_gitrepo=https://github.com/mits-lab/arch-configure-laptop.git

### Ensure critical variables above are filled out.

if [ -z "$_hostname" ]; then
    echo -n -e "\n Missing HOSTNAME variable...exiting\n"
    exit 1
fi
if [ -z "$_rootpass" ]; then
    echo -n -e "\nMissing ROOT PASSWORD variable...exiting\n"
    exit 1
fi
if [ -z "$_bootpass" ]; then
    echo -n -e "\nMissing Unlock OS Password variable...exiting\n"
    exit 1
fi

### Internet connection test

echo -n -e "\nTesting Internet Connectivity.."

if nc -zw1 $_urltest 443 && echo |openssl s_client -connect $_urltest:443 2>&1 |awk '
  handshake && $1 == "Verification" { if ($2=="OK") exit; exit 1 }
  $1 $2 == "SSLhandshake" { handshake = 1 }'
then
  echo -n -e ".$cyan Complete$normal \n"
else
  echo -n -e "\n\nNo internet connectivity detected.\n\nCheck you internet connection and re-run the script.\n"
  exit 1
fi

### offer to shred old drive contents.

echo -n -e "\nAlthough the script itself will automatically purge drive contents, in some rare conditions old EFI/MBR contents may remain.\n"
echo -n -e "Should the system fail to boot after completing the installation script, please consider shredding the drive contents on subsequent attempts.\n\n"

read -p "Run drive shred now?(y/n) " -n 1 -r
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo -n -e "\n"
else
    echo -n -e "\n\nShredding drive contents.."
    shred -v -n1 /dev/nvme0n1 >/dev/null 2>&1
    echo -n -e ".$cyan Complete$normal \n"
fi

### Prevent Script from running a second time.

if [ -e /root/.stop_run ]
then
    echo -n -e "\nScript has already completed system configuration.  Stopping..\n\n"
	exit 1
else
    echo -n -e "\nAdjusting Repo Locality.."
fi

touch /root/.stop_run

### Updates the packages on the system from the distribution repositories. 
##  The script finishes with a reboot.

# Set repo locality with 'reflector'

yes | pacman -S reflector >/dev/null 2>&1
reflector -c Canada -a 6 --sort rate --save /etc/pacman.d/mirrorlist >/dev/null 2>&1

echo -n -e ".$cyan Complete$normal \n"

#Update Pacman mirror list with the following.

echo -n -e "\nUpdating Repo List.."

yes | pacman -Sy >/dev/null 2>&1

echo -n -e ".$cyan Complete$normal \n"

# wipe the NVME drive before configuring.

echo -n -e "\nCleaning disks."

if cryptsetup -q open --type plain -d /dev/urandom /dev/nvme0n1 to_be_wiped >/dev/null 2>&1 ; then
    echo -n -e "."
else
    echo -n -e "Command failed. This probably because the disk is inaccessible (possibly because the disk is encrypted already by dmcrypt). Run the following dd command followed by a reboot.\n\n"
    echo -n -e "dd if=/dev/zero of=/dev/mapper/to_be_wiped bs=1M status=progress && reboot \n\n"
	exit 9
fi

dd if=/dev/zero of=/dev/mapper/to_be_wiped bs=1M status=none >/dev/null 2>&1
cryptsetup close to_be_wiped >/dev/null 2>&1

echo -n -e ".$cyan Complete$normal \n"

echo -n -e "\nPreparing disk geometry.."

# Create GPT filesystem table and add partitions to NVME disk

sgdisk -Z /dev/nvme0n1 >/dev/null 2>&1
sgdisk -n 1:2048:+200MiB -t 1:ef00 -c 0:grub /dev/nvme0n1 >/dev/null 2>&1
sgdisk -n 2::0 -t 2:8e00 -c 0:lvm /dev/nvme0n1 >/dev/null 2>&1

echo -n -e ".$cyan Complete$normal \n"

echo -n -e "\nInstalling dmcrypt partition encryption.."

# Use dmcrypt to encrypt partition 2

echo -n "$_bootpass" | cryptsetup luksFormat /dev/nvme0n1p2 -  >/dev/null 2>&1
echo -n "$_bootpass" | cryptsetup open /dev/nvme0n1p2 cryptlvm  >/dev/null 2>&1

echo -n -e ".$cyan Complete$normal \n"

# Create LVM partitions

echo -n -e "\nConfiguring LVM system partitions.."

pvcreate /dev/mapper/cryptlvm >/dev/null 2>&1
vgcreate MyVolGroup /dev/mapper/cryptlvm >/dev/null 2>&1
lvcreate -L 16G MyVolGroup -n swap >/dev/null 2>&1
lvcreate -L 32G MyVolGroup -n root >/dev/null 2>&1
lvcreate -L 120G MyVolGroup -n home >/dev/null 2>&1

echo -n -e ".$cyan Complete$normal \n"

# Add filesystems to LVM partitions

echo -n -e "\nFormatting the filesystem.."

mkfs.ext4 /dev/MyVolGroup/root >/dev/null 2>&1
mkfs.ext4 /dev/MyVolGroup/home >/dev/null 2>&1
mkswap /dev/MyVolGroup/swap >/dev/null 2>&1

echo -n -e ".$cyan Complete$normal \n"

# Mount LVM partitions

echo -n -e "\nMounting LVM partitions.."

mount /dev/MyVolGroup/root /mnt >/dev/null 2>&1
mkdir /mnt/home >/dev/null 2>&1
mount /dev/MyVolGroup/home /mnt/home >/dev/null 2>&1
swapon /dev/MyVolGroup/swap >/dev/null 2>&1

echo -n -e ".$cyan Complete$normal \n"

# Add filsystem to EFI directory.

echo -n -e "\nFormatting EFI partition.."

mkfs.fat -F32 /dev/nvme0n1p1 >/dev/null 2>&1

echo -n -e ".$cyan Complete$normal \n"

# Mount EFI partition

echo -n -e "\nMounting EFI boot partition.."

mkdir /mnt/boot >/dev/null 2>&1
mount /dev/nvme0n1p1 /mnt/boot >/dev/null 2>&1

echo -n -e ".$cyan Complete$normal \n"

# Install Base Packages

echo -n -e "\nInstalling Base Packages.."

yes '' | pacstrap -i /mnt base linux linux-firmware vim intel-ucode lvm2  >/dev/null 2>&1

echo -n -e ".$cyan Complete$normal \n"

# Generate the fstab for the root installation.

echo -n -e "\nGenerating the fstab.."

genfstab -U /mnt >> /mnt/etc/fstab

echo -n -e ".$cyan Complete$normal \n"

# Generate script installation to be executed within the 'arch-chroot' environment.

echo -n -e "\nConfiguring the bootstrapped system via chroot.."

# Configure base system

arch-chroot /mnt /usr/bin/bash <<EOF > /dev/null 2>&1
# set hostname
echo $_hostname > /etc/hostname
sed -i "/localhost/s/$/ $hostname/" /etc/hosts
#
# set timezone
ln -sf /usr/share/zoneinfo/America/Toronto /etc/localtime
hwclock --systohc
#
# generate locale
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
export LANG=en_US.UTF-8
echo "LANG=en_US.UTF-8" >> /etc/locale.conf
#
# Installing system packages
if pacman -S --noconfirm grub efibootmgr xf86-video-intel alsa-ucm-conf alsa-utils sof-firmware networkmanager network-manager-applet wireless_tools iw tlp wpa_supplicant dialog os-prober mtools dosfstools base-devel linux-headers git nmap reflector bluez bluez-utils pulseaudio-bluetooth cups xdg-utils xdg-user-dirs >/dev/null 2>&1 ; then
    echo -n -e ""
else
    echo -n -e "Command failed. Check arch-chroot pacman installation string manually to identify the failure.\n\n"
	exit 9
fi
#
# Set root password
echo "root:${_rootpass}" | chpasswd
#
# Customize default user's skel(eleton) directory.
mkdir /etc/skel/Documents
mkdir /etc/skel/Downloads
mkdir /etc/skel/Music
mkdir /etc/skel/Pictures
mkdir /etc/skel/Public
mkdir /etc/skel/Scripts
mkdir /etc/skel/Templates
mkdir /etc/skel/Video
mkdir /etc/skel/Scripts
# enable wheel as the sudoers group
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
# Generating initramfs
sed -i 's/^HOOKS.*/HOOKS="base udev keyboard keymap autodetect modconf block encrypt lvm2 filesystems fsck"/' /etc/mkinitcpio.conf
mkinitcpio -p linux
# enable Network Manager.
systemctl enable NetworkManager.service
# enable Bluetooth.
systemctl enable bluetooth.service
# enable cups
systemctl enable cups.service
# enable TLP - for laptop power management
systemctl enable tlp.service
# Pull configuration script
curl https://raw.githubusercontent.com/mits-lab/arch-configure-laptop/main/configure.sh > /root/configure.sh && chmod u+x /root/configure.sh >/dev/null 2>&1
EOF

echo -n -e ".$cyan Complete$normal \n"

# Configuring grub bootloader via chroot

echo -n -e "\nConfiguring the bootloader via chroot.."

arch-chroot /mnt /usr/bin/bash <<EOF > /dev/null 2>&1
# configure grub
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT.*|GRUB_CMDLINE_LINUX_DEFAULT="quiet cryptdevice=/dev/nvme0n1p2:cryptlvm root=/dev/MyVolGroup/root"|' /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg
EOF

echo -n -e ".$cyan Complete$normal \n"
echo -n -e "\n"

# unmounting partitions before offering reload option

#umount -a >/dev/null 2>&1

read -p "Your system will require a reboot to complete the installation.  Reboot now?(y/n) " -n 1 -r
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo -n -e "\n"
else
	echo -n -e "\n\nRebooting.. \n"
	reboot
	exit 0
fi

exit 0
