* sync system clock
  ```
  ntpd -g -q
  ```
* prepare disks, raids, crypts, and logical volumes. make and mount filesystems
  ```
  emerge sys-fs/cryptsetup sys-fs/lvm2 sys-fs/mdadm
  # TODO
  ```
* extract stage3 system tarball
  ```
  tar xpf stage3-*.tar.bz2 \
    --xattrs-include='*.*' \
    --numeric-owner \
    --directory=/mnt/gentoo
  ```
* update compile flags in //etc/portage/make.conf
  ```
  sed \
    --in-place \
    --expression='s#COMMON_FLAGS="(.*)"#COMMON_FLAGS="-march=native -O2 -pipe"#' \
    /mnt/gentoo/etc/portage/make.conf
  ```
* add use flags in //etc/portage/make.conf
  ```
  sed --in-place --expression 'd#^USE=.*$#' /mnt/gentoo/etc/portage/make.conf
  echo "USE=\"-consolekit systemd\"" >> /mnt/gentoo/etc/portage/make.conf
  ```
* add accepted licenses to //etc/portage/make.conf
  ```
  sed --in-place --expression 'd#^ACCEPT_LICENSE=.*$#' /mnt/gentoo/etc/portage/make.conf
  echo "ACCEPT_LICENSE=\"-* @FREE\"" >> /mnt/gentoo/etc/portage/make.conf
  mkdir --parents /mnt/gentoo/etc/portage/package.license
  echo 'sys-kernel/linux-firmware @BINARY-REDISTRIBUTABLE' > /mnt/gentoo/etc/portage/package.license/kernel
  ```
* add makeopts to //etc/portage/make.conf
  ```
  sed --in-place --expression 'd#^MAKEOPTS=.*$#'
  echo "MAKEOPTS=\"--jobs=$(($(nprocs)+1))\"" >> /mnt/gentoo/etc/portage/make.conf
  ```
* add mirrors to //etc/portage/make.conf
  ```
  sed --in-place --expression 'd#^GENTOO_MIRRORS=.*$#'
  mirrorselect -servers 3 -blocksize 10 -o >> /mnt/gentoo/etc/portage/make.conf
  ```
* add grub platforms to //etc/portage/make.conf
  ```
  sed --in-place --expression 'd#^GRUB_PLATFORMS=.*$#'
  echo "GRUB_PLATFORMS=\"efi-64\"" >> /mnt/gentoo/etc/portage/make.conf
  ```
* create gentoo repo config file
  ```
  mkdir --parents /mnt/gentoo/etc/portage/repos.conf
  cp \
    --dereference \
    --force \
    /mnt/gentoo/usr/share/portage/config/repos.conf \
    /mnt/gentoo/etc/portage/repos.conf/gentoo.conf
  ```
* copy resolv conf
  ```
  cp \
    --dereference \
    --force \
    /etc/resolv.conf \
    /mnt/gentoo/etc/resolv.conf
  ```
* configure systemd
  ```
  (
    timezone="$(
      echo "$(curl http://ip-api.com/json)" |
      sed --expression 's#.*\"timezone\":\"\([^\"]*\)\".*#\1#'
    )"
    test -f "/mnt/gentoo/usr/share/zoneinfo/$timezone"
    chroot /mnt/gentoo systemd-firstboot \
      --timezone="$timezone" \
      --hostname=gentoo-vm \
      --root-password=password \
      --copy-locale \
      --copy-kepmap \
      --setup-machine-id
  )
  ```
* link mtab
  ```
  ln \
    --symbolic \
    --force \
    /proc/self/mounts \
    /mnt/gentoo/etc/mtab
  ```
* mount special host filesystems
  ```
  mount --types proc /proc /mnt/gentoo/proc
  mount --rbind /sys /mnt/gentoo/sys
  mount --make-rslave /mnt/gentoo/sys
  mount --rbind /dev /mnt/gentoo/dev
  mount --make-rslave /mnt/gentoo/dev
  ```
* make a swapfile
  ```
  (
    memory="$(free --mega | grep '^Mem:' | awk '{print $2}')"
    dd if=/dev/zero of=/mnt/gentoo/tmp/swapfile bs="${memory}M" count=1000
  )
  mkswap /mnt/gentoo/tmp/swapfile
  swapon /mnt/gentoo/tmp/swapfile
  ```
* configure portage
  ```
  chroot /mnt/gentoo emerge-webrsync
  chroot /mnt/gentoo emerge --sync
  ```
* (optionally) change the base install profile
  ```
  chroot /mnt/gentoo eselect profile list
  chroot /mnt/gentoo eselect profile set <N>
  ```
* update the @world set
  ```
  chroot /mnt/gentoo emerge --update --deep --newuse @world
  ```
* install kernel sources and dependencies
  ```
  mkdir --parents /mnt/gentoo/etc/portage/package.use
  echo 'sys-kernel/gentoo-sources symlink' > /mnt/gentoo/etc/portage/package.use/kernel
  chroot /mnt/gentoo emerge \
    sys-fs/cryptsetup \
    sys-fs/lvm2 \
    sys-fs/mdadm \
    sys-kernel/gentoo-sources \
    sys-kernel/linux-firmware
  ```
* install kernel generation tools
  ```
  chroot /mnt/gentoo emerge sys-kernel/dracut sys-kernel/genkernel-next
  echo 'add_dracutmodules+="usrmount"' > /mnt/gentoo/etc/dracut.conf.d/usrmount.conf
  echo 'UDEV="YES"' > /mnt/gentoo/etc/genkernel.conf
  ```
* compile and install the kernel
  ```
  chroot /mnt/gentoo \
    /bin/bash -c ' \
      source /etc/portage/make.conf && \
      genkernel \
        --logfile=/tmp/genkernel.log \
        --splash --install \
        --makeopts="$MAKEOPTS" \
        --do-keymap-auto --keymap --udev --lvm --mdadm --luks --gpg \
        all'
  ```
Required kernel parameters:
  root=/dev/$ROOT (where $ROOT is device partition hosting root filesystem)
Optional kernel parameters:
  vga=791 splash=silent,theme:default console=tty quiet
  dolvm
  domdadm
  rootfstype=etx4
* populate //etc/fstab
  ```
  (
    uuid="$(blkid | grep /dev/sda3 | sed --expression='s#.*UUID="\(.*\)".*#\1#')"
    echo "UUID=\"$uuid\" / ext4 noatime 0 1" >> /mnt/gentoo/etc/fstab
  )
  (
    uuid="$(blkid | grep /dev/sda2 | sed --expression='s#.*UUID="\(.*\)".*#\1#')"
    echo "UUID=\"$uuid\" /boot vfat noatime 0 2" >> /mnt/gentoo/etc/fstab
  )
  ```
* install misc tools
  ```
  chroot /mnt/gentoo emerge \
    net-misc/dhcpcd \
    sys-apps/mlocate \
    sys-fs/dosfstools \
    sys-fs/e2fsprogs \
    sys-process/systemd-cron
  ln --symbolic --force \
    /lib/systemd/system/cron.target \
    /mnt/gentoo/etc/systemd/system/multi-user.target.wants/cron.target
  ```
  (optionally) Install wireless tools
  ```
  net-wireless/iw net-wireless/wpa_supplicant
  ```
* install bootloader
  ```
  chroot /mnt/gentoo emerge sys-boot/grub:2
  chroot /mnt/gentoo grub-install /dev/sda
  ```
  or with UEFI
  ```
  chroot /mnt/gentoo \
    mount -o remount,rw /sys/firmware/efi/efivars
  chroot /mnt/gentoo \
    grub-install --target=x86_64-efi --efi-directory=/boot --removable
  ```
* configure bootloader
  ```
  echo "GRUB_CMDLINE_LINUX=\"root=UUID=$(blkid | grep /dev/sda3 | sed --expression='s#.*UUID="\(.*\)".*#\1#') rootfstype=ext4 dolvm domdadm vga=791 splash=silent,theme:default console=tty quiet\"" >> /etc/default/grub
  mkdir --parents /boot/grub
  chroot /mnt/gentoo grub-mkconfig -o /boot/grub/grub.cfg
  ```
