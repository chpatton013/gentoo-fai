#!/usr/bin/env bash
set -xeuo pipefail

# Required arguments:
#   FAI_INSTALL_STAGE3_TAR
#   FAI_INSTALL_FSTAB
#   FAI_SYSTEMD_ROOT_PASSWORD
#   FAI_BOOTLDR_BOOT_DEVICE
#
# Optional arguments:
#   FAI_INSTALL_ROOT
#   FAI_INSTALL_SWAP
#   FAI_INSTALL_SWAP_MB
#   FAI_FEATURE_UEFI
#   FAI_FEATURE_WIRELESS
#   FAI_FEATURE_KERNEL_OLDCONFIG
#   FAI_FEATURE_KERNEL_MENUCONFIG
#   FAI_FEATURE_KERNEL_CONFIG
#   FAI_PORTAGE_COMPILE_FLAGS
#   FAI_PORTAGE_USE_FLAGS
#   FAI_PORTAGE_ACCEPT_LICENSE
#   FAI_PORTAGE_MAKEOPTS
#   FAI_PORTAGE_MIRRORS
#   FAI_PORTAGE_GRUB_PLATFORMS
#   FAI_SYSTEMD_LOCALE
#   FAI_SYSTEMD_KEYMAP
#   FAI_SYSTEMD_TIMEZONE
#   FAI_SYSTEMD_HOSTNAME
#   FAI_SYSTEMD_MACHINE_ID
#   FAI_BOOTLDR_EFI_TARGET
#   FAI_BOOTLDR_EFI_DIRECTORY
#   FAI_BOOTLDR_CMDLINE

# Basic install options
stage3_tar="$FAI_INSTALL_STAGE3_TAR"
install_root="${FAI_INSTALL_ROOT:-/mnt/gentoo}"
swap="${FAI_INSTALL_SWAP:-}"
swap_mb="${FAI_INSTALL_SWAP_MB:-}"
if [ -z "$swap_mb" ]; then
  swap_mb="$(free --mega | grep '^Mem:' | awk '{print $2}')"
fi
fstab="$FAI_INSTALL_FSTAB"

# Feature selection options
uefi="${FAI_FEATURE_UEFI:-}"
wireless="${FAI_FEATURE_WIRELESS:-}"
kernel_oldconfig="${FAI_FEATURE_KERNEL_OLDCONFIG:-}"
kernel_menuconfig="${FAI_FEATURE_KERNEL_MENUCONFIG:-}"
kernel_config="${FAI_FEATURE_KERNEL_CONFIG:-}"

# Portage options
compile_flags="${FAI_PORTAGE_COMPILE_FLAGS:-'-march=native -O2 -pipe'}"
use_flags="${FAI_PORTAGE_USE_FLAGS:-'-consolekit systemd'}"
accept_license="${FAI_PORTAGE_ACCEPT_LICENSE:-'-* @FREE'}"
makeopts="${FAI_PORTAGE_MAKEOPTS:-}"
if [ -z "$makeopts" ]; then
  cpus="$(grep '^processor\s*:' /proc/cpuinfo | wc --lines)"
  makeopts="--jobs=$((cpus + 1))"
fi
gentoo_mirrors="${FAI_PORTAGE_MIRRORS:-}"
if [ -z "$gentoo_mirrors" ]; then
  gentoo_mirrors="$(
    mirrorselect --country USA --servers 3 --blocksize 10 |
      sed --expression='s#GENTOO_MIRRORS="\(.*\)"#\1#'
  )"
fi
grub_platforms="${FAI_PORTAGE_GRUB_PLATFORMS:-}"
if [ -z "$uefi" ]; then
  grub_platforms+=' efi-64'
fi

# Systemd options
locale="${FAI_SYSTEMD_LOCALE:-}"
keymap="${FAI_SYSTEMD_KEYMAP:-}"
timezone="${FAI_SYSTEMD_TIMEZONE:-}"
if [ -z "$timezone" ]; then
  timezone="$(
    echo "$(curl http://ip-api.com/json)" |
      sed --expression 's#.*\"timezone\":\"\([^\"]*\)\".*#\1#'
  )"
fi
hostname="${FAI_SYSTEMD_HOSTNAME:-gentoo}"
machine_id="${FAI_SYSTEMD_MACHINE_ID:-}"
root_password="$FAI_SYSTEMD_ROOT_PASSWORD"

# Bootloader options
efi_target="${FAI_BOOTLDR_EFI_TARGET:-x86_64-efi}"
efi_directory="${FAI_BOOTLDR_EFI_DIRECTORY:-/boot}"
boot_device="$FAI_BOOTLDR_BOOT_DEVICE"
grub_cmdline_linux="${FAI_BOOTLDR_CMDLINE:-}"
if [ -z "$grub_cmdline_linux" ]; then
  grub_cmdline_linux+=" root=$boot_device rootfstype=ext4 dolvm domdadm"
  grub_cmdline_linux+=' vga=791 splash=silent,theme:default'
  grub_cmdline_linux+=' console=tty quiet'
fi

function ensure_file() {
  local file
  file="$1"
  readonly file

  mkdir --parents "$(dirname "$file")"
  touch "$file"
}

function populate_file() {
  local file content
  file="$1"
  content="$2"
  readonly file content

  ensure_file "$file"
  echo "$content" >"$file"
}

function replace_lines() {
  local file search replace
  file="$1"
  search="$2"
  replace="$3"
  readonly file search replace

  ensure_file "$file"
  sed --expression="s#$search#$replace#g" --in-place "$file"
}

function delete_lines() {
  local file pattern
  file="$1"
  pattern="$2"
  readonly file pattern

  ensure_file "$file"
  sed --expression="s#^$pattern\$##g" --in-place "$file"
}

function append_line() {
  local file line
  file="$1"
  line="$2"
  readonly file line

  ensure_file "$file"
  echo "$line" >>"$file"
}

function delete_and_append_lines() {
  local file delete append
  file="$1"
  delete="$2"
  append="$3"
  readonly file delete append

  delete_lines "$file" "$delete"
  append_line "$file" "$append"
}

function copy_file() {
  local source destination
  source="$1"
  destination="$2"
  readonly source destination

  mkdir --parents "$(dirname "$destination")"
  cp --dereference --force "$source" "$destination"
}

function link_file() {
  local source destination
  source="$1"
  destination="$2"
  readonly source destination

  mkdir --parents "$(dirname "$destination")"
  ln --symbolic --force "$source" "$destination"
}

echo Cleanup previous invocations
if mountpoint --quiet -- "$install_root/dev"; then
  umount --lazy "$install_root/dev"
fi
if mountpoint --quiet -- "$install_root/proc"; then
  umount --lazy "$install_root/proc"
fi
if mountpoint --quiet -- "$install_root/sys"; then
  umount --lazy "$install_root/sys"
fi
if [ ! -z "$swap" ] &&
    swapon --summary | grep --quiet "$install_root/tmp/swapfile"; then
  swapoff "$install_root/tmp/swapfile"
fi

echo Sync system clock
ntpd -g -q

echo Extract stage3 tarball
tar xpf "$stage3_tar" \
  --xattrs-include='*.*' \
  --numeric-owner \
  --directory="$install_root"

echo Set portage compile flags
replace_lines \
  "$install_root/etc/portage/make.conf" \
  'COMMON_FLAGS="(.*)"' \
  "COMMON_FLAGS=\"$compile_flags\""

echo Set portage use flags
delete_and_append_lines \
  "$install_root/etc/portage/make.conf" \
  'USE=.*' \
  "USE=\"$use_flags\""
populate_file \
  "$install_root/etc/portage/package.use/kernel" \
  'sys-kernel/gentoo-sources symlink'

echo Set portage accepted licenses
delete_and_append_lines \
  "$install_root/etc/portage/make.conf" \
  'ACCEPT_LICENSE=.*' \
  "ACCEPT_LICENSE=\"$accept_license\""
populate_file \
  "$install_root/etc/portage/package.license/kernel" \
  'sys-kernel/linux-firmware @BINARY-REDISTRIBUTABLE'

echo Set portage makeopts
delete_and_append_lines \
  "$install_root/etc/portage/make.conf" \
  'MAKEOPTS=.*' \
  "MAKEOPTS=\"$makeopts\""

echo Set portage mirrors
delete_and_append_lines \
  "$install_root/etc/portage/make.conf" \
  'GENTOO_MIRRORS=.*' \
  "GENTOO_MIRRORS=\"$gentoo_mirrors\""

echo Set portage grub platforms
delete_and_append_lines \
  "$install_root/etc/portage/make.conf" \
  'GRUB_PLATFORMS=.*' \
  "GRUB_PLATFORMS=\"$grub_platforms\""

echo Copy gentoo repo config file
delete_lines \
  "$install_root/usr/share/portage/config/repos.conf" \
  'sync-openpgp-keyserver = .*'
copy_file \
  "$install_root/usr/share/portage/config/repos.conf" \
  "$install_root/etc/portage/repos.conf/gentoo.conf"

echo Copy resolv.conf
copy_file /etc/resolv.conf "$install_root/etc/resolv.conf"

echo Link mtab
link_file /proc/self/mounts "$install_root/etc/mtab"

echo Mount special host filesystems
mount --types proc /proc "$install_root/proc"
mount --rbind /sys "$install_root/sys"
mount --make-rslave "$install_root/sys"
mount --rbind /dev "$install_root/dev"
mount --make-rslave "$install_root/dev"

if [ ! -z "$swap" ]; then
  echo Create a swapfile
  dd if=/dev/zero of="$install_root/tmp/swapfile" bs=1M count="$swap_mb"
  mkswap "$install_root/tmp/swapfile"
  swapon "$install_root/tmp/swapfile"
fi

echo Configure systemd
systemd_firstboot_args=
if [ -z "$locale" ]; then
  systemd_firstboot_args+=' --copy-locale'
else
  systemd_firstboot_args+=" --locale=$locale"
fi
if [ -z "$keymap" ]; then
  systemd_firstboot_args+=' --copy-keymap'
else
  systemd_firstboot_args+=" --keymap=$keymap"
fi
if [ -z "$machine_id" ]; then
  systemd_firstboot_args+=' --setup-machine-id'
else
  systemd_firstboot_args+=" --machine-id=$machine_id"
fi
chroot "$install_root" systemd-firstboot \
  $systemd_firstboot_args \
  --timezone="$timezone" \
  --hostname="$hostname" \
  --root-password="$root_password"

echo Configure portage
chroot "$install_root" emerge-webrsync
chroot "$install_root" emerge --sync
chroot "$install_root" emerge --update --deep --newuse @world

echo Install kernel sources and dependencies
chroot "$install_root" emerge \
  sys-fs/cryptsetup \
  sys-fs/lvm2 \
  sys-fs/mdadm \
  sys-kernel/gentoo-sources \
  sys-kernel/linux-firmware

echo Install kernel generation tools
chroot "$install_root" emerge sys-kernel/dracut sys-kernel/genkernel-next
populate_file \
  "$install_root/etc/dracut.conf.d/usrmount.conf" \
  'add_dracutmodules+="usrmount"'
populate_file "$install_root/etc/genkernel.conf" 'UDEV="YES"'

echo Compile and install the kernel
genkernel_args=
if [ ! -z "$kernel_oldconfig" ]; then
  genkernel_args+=' --oldconfig'
fi
if [ ! -z "$kernel_menuconfig" ]; then
  genkernel_args+=' --menuconfig'
fi
if [ ! -z "$kernel_config" ]; then
  genkernel_args+=" --kernel-config=$kernel_config"
fi
chroot "$install_root" /bin/bash -c " \
  source /etc/portage/make.conf && \
  genkernel \
    --logfile=/tmp/genkernel.log \
    $genkernel_args --save-config \
    --no-clean --no-mrproper --install \
    --makeopts=\"\$MAKEOPTS\" \
    --splash --do-keymap-auto --keymap --udev --lvm --mdadm --luks --gpg \
    all"

echo Populate fstab
populate_file "$install_root/etc/fstab" "$fstab"

echo Install miscellaneous tools
chroot "$install_root" emerge \
  net-misc/dhcpcd \
  sys-apps/mlocate \
  sys-fs/dosfstools \
  sys-fs/e2fsprogs \
  sys-process/systemd-cron
link_file \
  /lib/systemd/system/cron.target \
  "$install_root/etc/systemd/system/multi-user.target.wants/cron.target"

if [ ! -z "$wireless" ]; then
  echo Install wireless tools
  chroot "$install_root" emerge net-wireless/iw net-wireless/wpa_supplicant
fi

echo Install bootloader
if [ -z "$uefi" ]; then
  chroot "$install_root" mount -o remount,rw /sys/firmware/efi/efivars
  chroot "$install_root" grub-install \
    --target="$efi_target" \
    --efi-directory="$efi_directory"
else
  chroot "$install_root" emerge sys-boot/grub:2
  chroot "$install_root" grub-install "$boot_device"
fi

echo Configure bootloader
delete_and_append_lines \
  "$install_root/etc/default/grub" \
  'GRUB_CMDLINE_LINUX=.*' \
  "GRUB_CMDLINE_LINUX=\"$grub_cmdline_linux\""
ensure_file "$install_root/boot/grub/grub.cfg"
chroot "$install_root" grub-mkconfig -o /boot/grub/grub.cfg
