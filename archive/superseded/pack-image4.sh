#!/bin/bash
# Verify v4 against the working ArkOS card's contract, then compress.
set -u
IMG=/root/r36/out/r36max2-ubuntu-v4.img
OUTWIN=/mnt/e/ubuntu/out

echo "=== blob placement vs ArkOS expectations ==="
echo -n "  idbloader@32KiB first4: "; dd if="$IMG" bs=1 skip=32768 count=4 status=none | xxd -p
echo -n "  (arkos file first4)   : "; dd if=/mnt/e/ubuntu/artifacts/arkos/idbloader.img bs=1 count=4 status=none | xxd -p
echo -n "  uboot@8MiB magic      : "; dd if="$IMG" bs=1 skip=8388608 count=6 status=none | tr -d '\0'; echo
echo -n "  trust@12MiB magic     : "; dd if="$IMG" bs=1 skip=12582912 count=4 status=none | tr -d '\0'; echo

losetup -P -f "$IMG"
LOOP=$(losetup -j "$IMG" | cut -d: -f1)
mkdir -p /mnt/v5/boot /mnt/v5/root
mount -o ro "${LOOP}p1" /mnt/v5/boot && mount -o ro "${LOOP}p2" /mnt/v5/root
echo "=== BOOT files (compare names with the working card) ==="
ls -la /mnt/v5/boot | tail -8
echo "=== boot.ini (must start with lowercase magic, use mmc 1:1 + uInitrd) ==="
cat /mnt/v5/boot/boot.ini
echo "=== uInitrd really a legacy u-boot image? ==="
dd if=/mnt/v5/boot/uInitrd bs=1 count=8 status=none | xxd -p
echo "  0x27051956 = legacy uImage magic (same as the working card)"
echo "=== our card's uInitrd header vs working card ==="
echo -n "  working card: "; dd if=J:/dev/null bs=1 count=0 status=none 2>/dev/null; head -c 8 /mnt/e/ubuntu/build/arkos-uInitrd-head 2>/dev/null | xxd -p 2>/dev/null || echo "(not sampled)"
UUID=$(blkid -s UUID -o value "${LOOP}p2")
echo "=== UUID consistency: $UUID ==="
grep -c "$UUID" /mnt/v5/boot/boot.ini /mnt/v5/boot/extlinux/extlinux.conf
echo "=== rootfs spot check ==="
for f in etc/wpa_supplicant/wpa_supplicant-wlan0.conf usr/sbin/sshd \
         lib/modules/6.12.79/extra/rocknix-singleadc-joypad.ko \
         lib/modules/6.12.79/extra/aic8800_fdrv.ko lib/firmware/aic8800DC; do
  printf "  %-56s " "$f"; [ -e "/mnt/v5/root/$f" ] && echo OK || echo MISSING
done
umount /mnt/v5/root /mnt/v5/boot; losetup -d "$LOOP"

echo "=== compress ==="
time xz -T0 -6 -c "$IMG" > "$OUTWIN/r36max2-ubuntu-v4.img.xz"
ls -la "$OUTWIN/r36max2-ubuntu-v4.img.xz"
cd "$OUTWIN" && sha256sum r36max2-ubuntu-v4.img.xz | tee r36max2-ubuntu-v4.img.xz.sha256
echo "=== V4 PACK DONE ==="
