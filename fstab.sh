#!/usr/bin/env bash
set -xeuo pipefail

function uuid() {
  local device
  device="$1"
  readonly device

  blkid | grep "$device" | sed --expression='s#.*UUID="\(.*\)".*#\1#'
}

function fsrow() {
  local device mountpoint fstype options
  device="$1"
  mountpoint="$2"
  fstype="$3"
  options="$4"
  readonly device mountpoint fstype options

  local pass
  if [ "$device" == / ]; then
    pass=1
  else
    pass=2
  fi
  readonly pass

  echo "UUID=\"$(uuid "$device")\" $mountpoint $fstype $options 0 $pass"
}

fsrow /dev/sda3 / ext4 noatime
fsrow /dev/sda2 /boot vfat noatime
