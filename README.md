# gentoo-fai

Fully-automated-installer for a new Gentoo Linux system

## Summary

This is a prototype/WIP attempt at documenting and automating the install of a
Gentoo Linux system. This project contains no dependencies other than what is
trivially available on the Gentoo Live Image install media.

To start, I have been running this on a VirtualBox VM with the following specs:
* 8GB storage
* 1 CPU
* 1GB System RAM
* 16MB Video RAM

The disk preparation and installer parameterization have been naively selected
to ease the debugging cycle.

The disk will look like this:
```
/dev/sda
  \_ 1 (begin=1, end=3, name=grub, flags=bios_grub)
  \_ 2 (begin=3, end=131, name=boot, flags=boot)
  \_ 3 (begin=131, end=-1, name=root)
```

The fstab will look like this:
```
(uuid-of-/dev/sda3) / ext4 noatime 0 1
(uuid-of-/dev/sda2) /boot vfat noatime 0 2
```

### Usage

```
./prepare.sh
FAI_INSTALL_STAGE3_TAR=/path/to/stage3.tar.bz2
FAI_INSTALL_SWAP=yes
FAI_INSTALL_FSTAB=$(./fstab.sh)
FAI_SYSTEMD_ROOT_PASSWORD=password
FAI_BOOTLDR_BOOT_DEVICE=/dev/sda
./install.sh
```

### Future work

Eventually I will build a tool to prepare the destination media according to a
configuration file. This will support:
* disk partitioning
* raid, encryption, and logical volumes
* file system formatting and mounting

That same tool will generate the appropriate tab files needed to automate the
preparation of those volumes and file systems on boot.

## License

`gentoo-fai` is licensed under the terms of the MIT License, as described in
[LICENSE.md](LICENSE.md)

## Contributing

Contributions are welcome in the form of bug reports, feature requests, or pull
requests.

Contribution to `gentoo-fai` is organized under the terms of the [Contributor
Covenant](CONTRIBUTOR_COVENANT.md).
