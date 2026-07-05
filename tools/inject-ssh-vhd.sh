#!/usr/bin/env bash
set -e

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <vhd_file> <ssh_private_key>"
    exit 1
fi

VHD_FILE="$1"
SSH_KEY="$2"

echo "Injecting $SSH_KEY into $VHD_FILE..."

chmod +w "$VHD_FILE"
sudo modprobe nbd max_part=8 || true
sudo qemu-nbd -d /dev/nbd0 || true
sudo qemu-nbd -c /dev/nbd0 -f vpc "$VHD_FILE"
sleep 2

sudo mount /dev/nbd0p1 /mnt || sudo mount /dev/nbd0p2 /mnt || sudo mount /dev/nbd0p3 /mnt

sudo mkdir -p /mnt/etc/ssh
sudo cp "$SSH_KEY" /mnt/etc/ssh/ssh_host_ed25519_key
sudo chmod 600 /mnt/etc/ssh/ssh_host_ed25519_key

sudo umount /mnt
sudo qemu-nbd -d /dev/nbd0

echo "Done!"
