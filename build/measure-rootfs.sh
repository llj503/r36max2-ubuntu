#!/bin/bash
# Measure how much the rootfs actually occupies, so we can size a compact image.
set -u
R=/root/r36/rootfs
echo "=== rootfs du ==="
du -sk "$R" 2>/dev/null | awk '{printf "rootfs KiB: %s  GiB: %.2f\n", $1, $1/1048576}'
echo "=== biggest dirs ==="
du -sk "$R"/* 2>/dev/null | sort -rn | head -12
echo "=== tooling in rootfs ==="
for b in sfdisk resize2fs findfs blkid partprobe fdisk losetup mkfs.ext4; do
  if [ -e "$R/usr/sbin/$b" ] || [ -e "$R/sbin/$b" ] || [ -e "$R/usr/bin/$b" ]; then
    echo "have $b"
  else
    echo "MISSING $b"
  fi
done
echo "=== host tooling ==="
for b in sfdisk resize2fs mkfs.fat mkimage xz rsync dd; do
  command -v "$b" >/dev/null 2>&1 && echo "host have $b" || echo "host MISSING $b"
done
echo "=== staged boot files from v9 ==="
ls -la /root/r36/stage 2>/dev/null | head -20
echo "=== build-info ==="
cat "$R/etc/r36max2-build-info" 2>/dev/null
