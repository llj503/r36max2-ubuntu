#!/bin/bash
# Verify v3 and compress to E:\ubuntu\out
set -u
IMG=/root/r36/out/r36max2-ubuntu-v3.img
OUTWIN=/mnt/e/ubuntu/out

echo "=== blobs ==="
echo -n "  idbloader@32KiB: "; dd if="$IMG" bs=1 skip=32768 count=4 status=none | xxd -p
echo -n "  uboot@8MiB     : "; dd if="$IMG" bs=1 skip=8388608 count=6 status=none | tr -d '\0'; echo
echo -n "  trust@12MiB    : "; dd if="$IMG" bs=1 skip=12582912 count=4 status=none | tr -d '\0'; echo

losetup -P -f "$IMG"
LOOP=$(losetup -j "$IMG" | cut -d: -f1)
mkdir -p /mnt/v4/boot /mnt/v4/root
mount -o ro "${LOOP}p1" /mnt/v4/boot && mount -o ro "${LOOP}p2" /mnt/v4/root
echo "=== BOOT partition ==="; ls -la /mnt/v4/boot | tail -10
echo "=== extlinux dir ==="; ls /mnt/v4/boot/extlinux
echo "=== primary entry: extlinux/extlinux.conf ==="; cat /mnt/v4/boot/extlinux/extlinux.conf
UUID=$(blkid -s UUID -o value "${LOOP}p2")
echo "=== rootfs UUID from image: $UUID ==="
grep -q "$UUID" /mnt/v4/boot/extlinux/extlinux.conf && echo "MATCH in extlinux.conf" || echo "MISMATCH!"
grep -q "$UUID" /mnt/v4/boot/boot.scr 2>/dev/null && echo "MATCH in boot.scr" || echo "(boot.scr is binary; checking strings)"
strings /mnt/v4/boot/boot.scr | grep -o "root=UUID=[a-f0-9-]*" | head -1
echo "=== rootfs spot check ==="
for f in etc/wpa_supplicant/wpa_supplicant-wlan0.conf usr/sbin/sshd \
         lib/modules/6.12.79/extra/rocknix-singleadc-joypad.ko \
         lib/modules/6.12.79/extra/aic8800_fdrv.ko lib/firmware/aic8800DC etc/hostname; do
  printf "  %-56s " "$f"; [ -e "/mnt/v4/root/$f" ] && echo OK || echo MISSING
done
cat /mnt/v4/root/etc/hostname
umount /mnt/v4/root /mnt/v4/boot; losetup -d "$LOOP"

echo "=== compress ==="
time xz -T0 -6 -c "$IMG" > "$OUTWIN/r36max2-ubuntu-v3.img.xz"
ls -la "$OUTWIN/r36max2-ubuntu-v3.img.xz"
cd "$OUTWIN" && sha256sum r36max2-ubuntu-v3.img.xz | tee r36max2-ubuntu-v3.img.xz.sha256
echo "=== DONE ==="
