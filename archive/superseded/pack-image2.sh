#!/bin/bash
# Verify the v2 (MBR) image and compress it to E:\ubuntu\out
set -u
IMG=/root/r36/out/r36max2-ubuntu.img
OUTWIN=/mnt/e/ubuntu/out

echo "=== partition table ==="
fdisk -l "$IMG" 2>/dev/null | tail -5
echo "=== blob placement ==="
echo -n "  idbloader@32KiB : "; dd if="$IMG" bs=1 skip=32768 count=4 status=none | xxd -p
echo -n "  uboot@8MiB      : "; dd if="$IMG" bs=1 skip=8388608 count=6 status=none | tr -d '\0'; echo
echo -n "  trust@12MiB     : "; dd if="$IMG" bs=1 skip=12582912 count=4 status=none | tr -d '\0'; echo

echo "=== mount and inspect ==="
losetup -P -f "$IMG"
LOOP=$(losetup -j "$IMG" | cut -d: -f1)
mkdir -p /mnt/v3/boot /mnt/v3/root
mount -o ro "${LOOP}p1" /mnt/v3/boot
mount -o ro "${LOOP}p2" /mnt/v3/root
echo "--- BOOT partition ---"; ls -la /mnt/v3/boot | tail -9
echo "--- extlinux ---"; ls /mnt/v3/boot/extlinux
echo "--- boot.ini first line ---"; head -1 /mnt/v3/boot/boot.ini
echo "--- bootargs line ---"; grep -m1 bootargs /mnt/v3/boot/boot.ini
echo "--- rootfs UUID matches boot.ini? ---"
BLKUUID=$(blkid -s UUID -o value "${LOOP}p2")
grep -q "$BLKUUID" /mnt/v3/boot/boot.ini && echo "MATCH $BLKUUID" || echo "MISMATCH!"
echo "--- rootfs key files ---"
for f in etc/wpa_supplicant/wpa_supplicant-wlan0.conf usr/sbin/sshd \
         lib/modules/6.12.79/extra/rocknix-singleadc-joypad.ko \
         lib/modules/6.12.79/modules.dep lib/firmware/aic8800DC; do
  printf "  %-56s " "$f"; [ -e "/mnt/v3/root/$f" ] && echo OK || echo MISSING
done
umount /mnt/v3/root /mnt/v3/boot; losetup -d "$LOOP"

echo "=== compress ==="
time xz -T0 -6 -c "$IMG" > "$OUTWIN/r36max2-ubuntu-v2.img.xz"
ls -la "$OUTWIN/r36max2-ubuntu-v2.img.xz"
sha256sum "$OUTWIN/r36max2-ubuntu-v2.img.xz" | tee "$OUTWIN/r36max2-ubuntu-v2.img.xz.sha256"
echo "=== PACK DONE ==="
