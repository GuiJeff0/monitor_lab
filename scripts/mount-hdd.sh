#!/usr/bin/env bash
# ==============================================================================
# Format & Mount HDD /dev/sda1 at /mnt/dados
# Configures persistent mount in /etc/fstab
# ==============================================================================
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root or with sudo: sudo $0"
   exit 1
fi

DEVICE="/dev/sda1"
MOUNT_POINT="/mnt/dados"

echo "=== Checking storage device ${DEVICE} ==="

if [ ! -b "$DEVICE" ]; then
    echo "Error: Block device $DEVICE does not exist."
    exit 1
fi

# Check if filesystem exists
FSTYPE=$(blkid -o value -s TYPE "$DEVICE" || true)

if [ -z "$FSTYPE" ]; then
    echo "No filesystem found on $DEVICE. Formatting as ext4..."
    mkfs.ext4 -L "dados" -m 1 "$DEVICE"
    FSTYPE="ext4"
else
    echo "Found existing filesystem: $FSTYPE"
fi

# Get UUID
UUID=$(blkid -o value -s UUID "$DEVICE")
echo "Device UUID: $UUID"

# Create mount point
mkdir -p "$MOUNT_POINT"

# Mount if not mounted
if ! grep -qs "$MOUNT_POINT" /proc/mounts; then
    echo "Mounting $DEVICE to $MOUNT_POINT..."
    mount "$DEVICE" "$MOUNT_POINT"
else
    echo "$MOUNT_POINT is already mounted."
fi

# Check fstab entry
if ! grep -q "$UUID" /etc/fstab; then
    echo "Adding persistent mount entry to /etc/fstab..."
    echo "UUID=${UUID} ${MOUNT_POINT} ${FSTYPE} defaults,noatime 0 2" >> /etc/fstab
    echo "Entry added to /etc/fstab."
else
    echo "Entry already present in /etc/fstab."
fi

# Create dedicated K3s storage directories
mkdir -p "${MOUNT_POINT}/k3s-storage"
mkdir -p "${MOUNT_POINT}/observability"
chmod 777 "${MOUNT_POINT}/k3s-storage"

echo "=== Mount verification ==="
df -h "$MOUNT_POINT"
echo "HDD setup completed successfully!"

