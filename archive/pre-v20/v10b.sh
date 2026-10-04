#!/bin/bash
# v10b: install the fixed expand script, re-pack, then dry-run expansion on a
# 4 GiB copy (loop devices do not expose /sys/block/<part>, so the script now
# parses `sfdisk -d` and uses blockdev).
set -eu
ROOT=/root/r36/rootfs
SRC=/mnt/e/ubuntu/build
K=/root/r36/linux-6.12.79
B=/tmp/v10dry.bin

cp -f "$SRC/r36-expand-root" "$ROOT/usr/local/sbin/r36-expand-root"
chmod 755 "$ROOT/usr/local/sbin/r36-expand-root"
sh -n "$ROOT/usr/local/sbin/r36-expand-root" && echo "expand script: syntax ok"

echo "=== misc sanity on the prepared rootfs ==="
ls -la "$ROOT/etc/ssh/" | grep -c host || echo "NO SSH HOST KEYS"
ls "$ROOT/etc/wpa_supplicant/" 2>/dev/null
dd if="$ROOT/../out/boot/Image" bs=1 skip=56 count=4 2>/dev/null | od -An -c

bash "$SRC/pack-v10.sh" 2>&1 | tail -12

echo "=== expansion dry run against a 4 GiB copy ==="
IMG=/root/r36/out/r36max2-ubuntu-v10.img
rm -f "$B"; cp --sparse=always "$IMG" "$B"; truncate -s 4G "$B"
losetup -D 2>/dev/null || true
losetup -P -f "$B"; D=$(losetup -j "$B" | cut -d: -f1); DD=${D#/dev/}
for _ in $(seq 1 40); do [ -b "${D}p2" ] && break; sleep 0.3; done
mkdir -p /mnt/v10root
mount "${D}p2" /mnt/v10root
cp /mnt/v10root/usr/local/sbin/r36-expand-root /tmp/x-expand.sh
sed -i "s#^ROOT=.*#ROOT=/dev/${DD}p2#" /tmp/x-expand.sh
sed -i "s#^MARK=.*#MARK=/mnt/v10root/var/lib/r36-expand-pending#" /tmp/x-expand.sh
echo "  blockdev --getsz $D = $(blockdev --getsz "$D") ; ${D}p2 = $(blockdev --getsz "${D}p2")"
sh /tmp/x-expand.sh
echo "  --- finisher (marker path) ---"
ls -la /mnt/v10root/var/lib/r36-expand-pending 2>/dev/null || echo "  no marker: grown online"
cp /mnt/v10root/usr/local/sbin/r36-finish-expand /tmp/x-finish.sh
sed -i "s#^MARK=.*#MARK=$B-marker#" /tmp/x-finish.sh
umount /mnt/v10root
losetup -d "$D"
rm -f "$B"
echo "=== V10B DONE ==="
