#!/usr/bin/env bash
set -e

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <vhd_file> <ssh_private_key>"
    exit 1
fi

VHD_FILE="$1"
SSH_KEY="$2"

function cleanup {
    echo "Cleaning up..."
    sudo umount -f /mnt 2>/dev/null || true
    sudo umount -l /mnt 2>/dev/null || true
    sudo qemu-nbd -d /dev/nbd0 2>/dev/null || true
}
trap cleanup EXIT

echo "Injecting $SSH_KEY into $VHD_FILE..."

chmod +w "$VHD_FILE"
sudo modprobe nbd max_part=8 || true
sudo qemu-nbd -d /dev/nbd0 2>/dev/null || true
sudo qemu-nbd -c /dev/nbd0 -f vpc "$VHD_FILE"
sleep 2

ROOT_PART=""
for part in /dev/nbd0p*; do
    # Use lsblk to check for typical Linux root filesystems
    FS_TYPE=$(lsblk -no FSTYPE "$part" | tr -d '[:space:]')
    if [[ "$FS_TYPE" == "ext4" || "$FS_TYPE" == "btrfs" || "$FS_TYPE" == "xfs" ]]; then
        ROOT_PART="$part"
        break
    fi
done

if [ -z "$ROOT_PART" ]; then
    echo "Error: Could not determine the root partition!"
    exit 1
fi

sudo mount "$ROOT_PART" /mnt

sudo mkdir -p /mnt/etc/ssh
sudo cp "$SSH_KEY" /mnt/etc/ssh/ssh_host_ed25519_key
sudo chmod 600 /mnt/etc/ssh/ssh_host_ed25519_key

echo "Done!"
