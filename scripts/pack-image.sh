#!/bin/bash
# Re-verify the 58G image, then compress it for flashing onto E:.
set -u
IMG=/root/r36/out/r36max2-ubuntu.img
OUTWIN=/mnt/e/ubuntu/out
mkdir -p "$OUTWIN"

echo "=== quick structural verify ==="
sgdisk -v "$IMG" 2>&1 | tail -2
sgdisk -p "$IMG" 2>&1 | sed -n '/Number/,/UBUNTU/p' | head -6
sgdisk -i 2 "$IMG" | grep -i "unique guid"
echo -n "idbloader@32K: "; dd if="$IMG" bs=1 skip=32768 count=4 status=none | xxd -p
echo -n "uboot@8M magic : "; dd if="$IMG" bs=1 skip=8388608 count=6 status=none | tr -d '\0'
echo
echo -n "trust@12M magic: "; dd if="$IMG" bs=1 skip=12582912 count=4 status=none | tr -d '\0'; echo

echo "=== content spot-check ==="
losetup -P -f "$IMG"
LOOP=$(losetup -j "$IMG" | cut -d: -f1)
mkdir -p /mnt/v2/boot /mnt/v2/root
mount -o ro "${LOOP}p1" /mnt/v2/boot && mount -o ro "${LOOP}p2" /mnt/v2/root
ls -la /mnt/v2/boot | tail -4
grep -m1 "root=PARTUUID" /mnt/v2/boot/boot.ini | cut -c1-80
ls /mnt/v2/root/lib/modules/6.12.79/extra/
umount /mnt/v2/root /mnt/v2/boot; losetup -d "$LOOP"

echo "=== compressing (this reads 58G of mostly-empty space) ==="
time xz -T0 -6 -c "$IMG" > "$OUTWIN/r36max2-ubuntu-26.04.img.xz"
ls -la "$OUTWIN/"
echo "=== sha256 ==="
sha256sum "$OUTWIN/r36max2-ubuntu-26.04.img.xz" | tee "$OUTWIN/r36max2-ubuntu-26.04.img.xz.sha256"
echo "=== DONE ==="
