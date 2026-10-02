#!/bin/bash
# Acceptance check of v12: boot.ini switch, both dtbs present, bootlog prints to screen.
set -uo pipefail
IMG=/root/r36/out/r36max2-ubuntu-v12.img
losetup -D 2>/dev/null || true
losetup -P -f "$IMG"; L=$(losetup -j "$IMG" | cut -d: -f1)
for _ in $(seq 1 40); do [ -b "${L}p1" ] && [ -b "${L}p2" ] && break; sleep 0.3; done
mkdir -p /mnt/a12b /mnt/a12r
mount -o ro "${L}p1" /mnt/a12b; mount -o ro "${L}p2" /mnt/a12r
echo "=== BOOT partition ==="
ls -la /mnt/a12b
echo "--- boot.ini ---"; cat /mnt/a12b/boot.ini
echo "=== rootfs: the on-screen summary ==="
grep -n 'dev/console' /mnt/a12r/usr/local/sbin/r36-bootlog
echo "--- console block it prints ---"
sed -n '/^WLAN=/,/dev\/console/p' /mnt/a12r/usr/local/sbin/r36-bootlog | head -22
echo "=== wpa units actually enabled ==="
ls /mnt/a12r/etc/systemd/system/multi-user.target.wants/ | tr '\n' ' '; echo
ls -l /mnt/a12r/etc/wpa_supplicant/ | tr -s ' '
echo "=== timers ==="
ls /mnt/a12r/etc/systemd/system/timers.target.wants/ | tr '\n' ' '; echo
echo "=== bootlog unit ==="
cat /mnt/a12r/etc/systemd/system/r36-bootlog.timer
umount /mnt/a12b /mnt/a12r; losetup -d "$L"
echo "=== DONE ==="
