#!/bin/bash
# GetMoreRam.sh - Interactive repartitioning to create swap
# VERY DANGEROUS: I am not responsible for sny data loss
set -euo pipefail

confirm() { read -p "$1 [y/N]: " ans; [[ "$ans" =~ ^[Yy]$ ]]; }

if [ "$EUID" -ne 0 ]; then
  echo "Run as root (sudo)."; exit 1
fi

echo "Current block devices:"
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,LABEL
echo
read -p "Enter disk device to modify (e.g. /dev/sda): " DISK
if [ ! -b "$DISK" ]; then echo "Device not found."; exit 1; fi

read -p "Enter desired swap size (e.g. 2G or 2048M): " SWAPSIZE

echo "Checking free space on $DISK..."
parted -m "$DISK" unit MiB print free | sed -n '1,200p'
FREE_BYTES=$(parted -m "$DISK" unit B print free | awk -F: '/free/ {print $3; exit}' | sed 's/B$//')
if [ -n "$FREE_BYTES" ] && [ "$FREE_BYTES" -gt 0 ]; then
  echo "Free space detected."
  if ! confirm "Create swap partition of $SWAPSIZE in free space on $DISK?"; then echo "Aborted."; exit 0; fi
  # create partition at end using parted (assumes free space at end)
  parted --script "$DISK" mkpart primary linux-swap 100% -"$SWAPSIZE"
else
  echo "No free space found."
  echo "Listing candidate partitions that can be shrunk (unmounted, ext2/3/4):"
  lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT | awk '/ext[234]/ || /ext[23]/ {print}'
  read -p "Enter partition to shrink (e.g. /dev/sda2) or 'cancel': " PART
  if [ "$PART" = "cancel" ]; then echo "Aborted."; exit 0; fi
  FSTYPE=$(lsblk -no FSTYPE "$PART")
  if [ "$FSTYPE" != "ext4" ] && [ "$FSTYPE" != "ext3" ] && [ "$FSTYPE" != "ext2" ]; then
    echo "Refusing to shrink $PART: unsupported filesystem ($FSTYPE). XFS cannot be shrunk; use backup/LVM or live media."; exit 1
  fi
  if mountpoint -q "$(lsblk -no MOUNTPOINT $PART)"; then
    echo "$PART is mounted. It must be unmounted to shrink."
    if ! confirm "Unmount $PART now?"; then echo "Aborted."; exit 1; fi
    umount "$PART"
  fi
  echo "Running filesystem check..."
  e2fsck -f "$PART"
  echo "Enter new size for $PART filesystem (e.g. 10G) — must be larger than used data:"
  read -p "New filesystem size: " NEWFS
  if ! confirm "Proceed to resize filesystem on $PART to $NEWFS? This is destructive on error."; then echo "Aborted."; exit 1; fi
  resize2fs "$PART" "$NEWFS"
  echo "Resizing partition table to match filesystem (parted will be used)."
  PARTNUM=$(lsblk -no PARTNUM "$PART")
  parted --script "$DISK" resizepart "$PARTNUM" 100% -"$SWAPSIZE"
fi

# refresh and find new swap partition (last partition)
partprobe "$DISK"
sleep 1
NEWPART=$(lsblk -ln "$DISK" | awk 'END{print $1}')
NEWPART="/dev/$NEWPART"
echo "Formatting $NEWPART as swap..."
mkswap "$NEWPART"
swapon "$NEWPART"
echo "$NEWPART none swap sw 0 0"
echo "Done. Verify with: swapon --show; free -h"
