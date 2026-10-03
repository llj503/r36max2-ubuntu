#!/bin/bash
# v20-verify.sh - the pack script verified the mounted image before compressing;
# this checks the archive itself and prints exactly what a card flashed from v20
# will contain on the bootable FAT partition.
set -uo pipefail
V=v20
IMGXZ=/mnt/e/ubuntu/out/r36max2-ubuntu-$V.img.xz
IMG=/root/r36/out/r36max2-ubuntu-$V.img

echo "=== sizes: v19 vs v20 ==="
ls -l /mnt/e/ubuntu/out/r36max2-ubuntu-v19.img.xz "$IMGXZ" 2>/dev/null | awk '{printf "  %12d  %s\n", $5, $9}'
echo "  raw image: $(ls -l "$IMG" | awk '{print $5}') bytes"

echo
echo "=== archive integrity ==="
time xz -t "$IMGXZ" && echo "  xz -t: OK"
echo "  sha256 file: $(cat "$IMGXZ.sha256" 2>/dev/null)"

echo
echo "=== re-mount the raw image and list the FAT partition (what Windows sees) ==="
M=/mnt/r36v20chk; rm -rf "$M"; mkdir -p "$M/boot" "$M/root"
losetup -D 2>/dev/null || true
losetup -P -f "$IMG"; LOOP=$(losetup -j "$IMG" | cut -d: -f1)
for i in 1 2; do for _ in $(seq 1 40); do [ -b "${LOOP}p$i" ] && break; sleep 0.3; done; done
mount -o ro "${LOOP}p1" "$M/boot"
echo "  BOOT (FAT) files:"
ls -l "$M/boot" | awk 'NR>1{printf "    %10d  %s\n", $5, $9}'
echo "  boot.ini loads: $(grep -oE 'Image[^ ]*|rk3326[^ ]*dtb' "$M/boot/boot.ini" | tr '\n' ' ')"
echo "  boot-612.ini loads: $(grep -oE 'Image[^ ]*|rk3326[^ ]*dtb' "$M/boot/boot-612.ini" | tr '\n' ' ')"
echo "  switches file bytes: $(stat -c%s "$M/boot/r36-switches.txt")"

echo
echo "=== root partition: the two kernels and their extras ==="
mount -o ro "${LOOP}p2" "$M/root"
for kv in 6.12.79 7.2.8; do
  echo "  /lib/modules/$kv: $(find "$M/root/lib/modules/$kv" -name '*.ko' | wc -l) .ko"
  for f in "$M/root/lib/modules/$kv/extra/"*.ko; do
    [ -e "$f" ] && echo "      $(basename "$f") $(stat -c%s "$f") B vermagic=$(modinfo -F vermagic "$f" | awk '{print $1}')"
  done
done
echo "  weston: $(ls "$M/root/usr/bin/weston" >/dev/null 2>&1 && echo installed)  enabled: $(ls "$M/root/etc/systemd/system/multi-user.target.wants/weston.service" 2>/dev/null || echo no)"
echo "  keymapper files: $(ls "$M/root/usr/local/bin/" | grep -E "r36-wayland|r36-keymapper|r36-shot" | tr '\n' ' ')"
echo "  ssh host keys: $(ls "$M/root/etc/ssh/ssh_host_*" 2>/dev/null | wc -l) (expect 0)"
echo "  creds: $(ls "$M/root/etc/wpa_supplicant/"*wlan0.conf 2>/dev/null | wc -l) (expect 0)"
echo "  build-info: $(cat "$M/root/etc/r36max2-build-info")"
echo "  rootfs used: $(df -h "$M/root" | tail -1 | awk '{print $3" of "$2" ("$5")"}')"

umount "$M/boot" "$M/root" 2>/dev/null; losetup -d "$LOOP"
echo "=== verify done ==="
