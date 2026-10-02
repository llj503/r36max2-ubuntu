#!/bin/bash
# Final offline acceptance check of the shipped v10 image.
set -uo pipefail
IMG=/root/r36/out/r36max2-ubuntu-v10.img
XZ=/mnt/e/ubuntu/out/r36max2-ubuntu-v10.img.xz

echo "=== sizes ==="
echo "raw image : $(stat -c %s "$IMG") bytes = $(( $(stat -c %s "$IMG") / 1048576 )) MiB"
echo "xz        : $(stat -c %s "$XZ") bytes"
echo "sha256    : $(cat "$XZ".sha256)"

echo "=== partition table (must be: p1 112M FAT32LBA bootable @32768, p2 2G @262144) ==="
sfdisk -d "$IMG" | tail -3

echo "=== rockchip blob placement ==="
for pair in "64:idbloader:RIFF:" "16384:uboot:U-Boot" "24576:trust:BL31"; do
  s=${pair%%:*}; rest=${pair#*:}; n=${rest%%:*}; m=${rest##*:}
  hit=$(dd if="$IMG" bs=512 skip="$s" count=64 2>/dev/null | strings -a | grep -m1 "$m" || true)
  echo "  @sector $s ($n): magic '$m' -> ${hit:-NOT FOUND}"
done

losetup -D 2>/dev/null || true
losetup -P -f "$IMG"; L=$(losetup -j "$IMG" | cut -d: -f1)
for _ in $(seq 1 40); do [ -b "${L}p1" ] && [ -b "${L}p2" ] && break; sleep 0.3; done
mkdir -p /mnt/f10b /mnt/f10r
mount -o ro "${L}p1" /mnt/f10b; mount -o ro "${L}p2" /mnt/f10r

echo "=== /boot (FAT) ==="
ls -la /mnt/f10b | tail -6
echo "  first line of boot.ini: $(head -1 /mnt/f10b/boot.ini)"
echo "  lines: $(wc -l < /mnt/f10b/boot.ini)"
for f in Image uInitrd rk3326-xifan-r36max2.dtb boot.ini extlinux/extlinux.conf; do
  [ -f "/mnt/f10b/$f" ] && echo "  ok   $f" || echo "  MISS $f"
done

echo "=== rootfs ==="
cat /mnt/f10r/etc/r36max2-build-info
echo "  /sbin/init        -> $(readlink /mnt/f10r/sbin/init)"
echo "  systemd binary    : $(du -h /mnt/f10r/lib/systemd/systemd | cut -f1)"
echo "  sfdisk/partx      : $(ls /mnt/f10r/usr/sbin/sfdisk /mnt/f10r/bin/partx 2>/dev/null | tr '\n' ' ')"
echo "  expand helpers    : $(ls /mnt/f10r/usr/local/sbin/ | tr '\n' ' ')"
echo "  expand script has SECTORS fix: $(grep -c 'o SECTORS' /mnt/f10r/usr/local/sbin/r36-expand-root)"
echo "  unit enabled      : $(ls /mnt/f10r/etc/systemd/system/multi-user.target.wants/ | grep r36 || echo none)"
echo "  extra modules     : $(ls /mnt/f10r/usr/lib/modules/6.12.79/extra/ | tr '\n' ' ')"
echo "  modules.dep       : $(test -f /mnt/f10r/usr/lib/modules/6.12.79/modules.dep && echo yes)"
echo "  aic firmware      : $(ls /mnt/f10r/lib/firmware/ | grep -i aic | tr '\n' ' ')"
echo "  wpa config        : $(test -f /mnt/f10r/etc/wpa_supplicant/wpa_supplicant-wlan0.conf && echo present) mode=$(stat -c %a /mnt/f10r/etc/wpa_supplicant/wpa_supplicant-wlan0.conf)"
echo "  ssh host keys     : $(ls /mnt/f10r/etc/ssh/ | grep -c 'host.*_key')"
echo "  network units     : $(ls /mnt/f10r/etc/systemd/network/ 2>/dev/null | tr '\n' ' ')"
echo "  users             : $(grep -c ':' /mnt/f10r/etc/passwd) accounts; sudo group: $(getent group sudo -s /mnt/f10r/etc/group 2>/dev/null || grep '^sudo:' /mnt/f10r/etc/group)"
echo "  df of the ext4    : $(df -h /mnt/f10r | tail -1 | awk '{print "size="$2" used="$3" avail="$4}')"
umount /mnt/f10b /mnt/f10r; losetup -d "$L"
echo "=== ACCEPTANCE DONE ==="
