#!/bin/bash
set -u
R=/root/r36/rootfs
echo "=== /var breakdown (KiB) ==="
du -sk "$R"/var/* 2>/dev/null | sort -rn | head -10
echo "=== /usr breakdown ==="
du -sk "$R"/usr/* 2>/dev/null | sort -rn | head -6
echo "=== helper binaries present? ==="
for b in lsblk partx findfs resize2fs sfdisk fdisk mkfs.ext4 awk sed grep blkid; do
  if chroot "$R" /bin/sh -c "command -v $b" >/dev/null 2>&1; then echo "have $b"; else echo "MISSING $b"; fi
done
echo "=== uInitrd ==="
ls -la /root/r36/out/boot/
echo "=== apt lists size ==="
du -sk "$R"/var/lib/apt/lists 2>/dev/null
