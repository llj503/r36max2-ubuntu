#!/bin/bash
# Verify the assembled R36 Max 2 image: partition table, blob offsets, boot files, rootfs sanity.
set -u
IMG=/root/r36/out/r36max2-ubuntu.img

echo "=== GPT ==="
sgdisk -v "$IMG" 2>&1 | tail -3
sgdisk -p "$IMG" 2>&1 | sed -n '/Number/,/^$/p' | head -8
echo "=== partition 2 PARTUUID (must match boot.ini) ==="
sgdisk -p "$IMG" | grep -A4 "Partition GUID code" >/dev/null; sgdisk -i 2 "$IMG" | grep -i "unique"

echo "=== blob signatures at expected offsets ==="
echo -n "  idbloader @32KiB : "; dd if="$IMG" bs=1 skip=32768 count=4 status=none | xxd -p
echo -n "  uboot @8MiB      : "; dd if="$IMG" bs=1 skip=8388608 count=8 status=none | xxd -p | head -c 16; echo
echo -n "  trust @12MiB     : "; dd if="$IMG" bs=1 skip=12582912 count=8 status=none | xxd -p | head -c 16; echo

echo "=== attach read-only for content check ==="
losetup -P -f "$IMG"
LOOP=$(losetup -j "$IMG" | cut -d: -f1)
mkdir -p /mnt/vfy/boot /mnt/vfy/root
mount -o ro "${LOOP}p1" /mnt/vfy/boot
mount -o ro "${LOOP}p2" /mnt/vfy/root

echo "--- boot partition ---"
ls -la /mnt/vfy/boot
echo "--- boot.ini ---"
cat /mnt/vfy/boot/boot.ini
echo "--- rootfs sanity ---"
for f in etc/hostname etc/machine-id etc/wpa_supplicant/wpa_supplicant-wlan0.conf \
         lib/modules/6.12.79/extra/rocknix-singleadc-joypad.ko \
         lib/firmware/aic8800DC/fmacfw_patch_8800dc_h_u02.bin \
         usr/sbin/sshd etc/modules-load.d/r36max2.conf; do
  printf "  %-58s " "$f"; [ -e "/mnt/vfy/root/$f" ] && echo OK || echo MISSING
done
echo "--- wpa config (passphrase hidden) ---"
sed 's/psk=.*/psk=<hidden>/' /mnt/vfy/root/etc/wpa_supplicant/wpa_supplicant-wlan0.conf | grep -E "ssid|psk|country"
echo "--- modules.dep has our extras? ---"
grep -c "extra/" /mnt/vfy/root/lib/modules/6.12.79/modules.dep
echo "--- users ---"
grep -E "^(root|ubuntu):" /mnt/vfy/root/etc/passwd

echo "=== dtb: does it describe this board? ==="
dtc -I dtb -O dts /mnt/vfy/boot/rk3326-xifan-r36max2.dtb 2>/dev/null | grep -m4 -E "model|compatible = \"rocknix|compatible = \"xifan|panel_description" | cut -c1-90

umount /mnt/vfy/root /mnt/vfy/boot
losetup -d "$LOOP"
echo "=== VERIFY DONE ==="
