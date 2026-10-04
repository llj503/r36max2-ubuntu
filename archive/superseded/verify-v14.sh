#!/bin/bash
set -uo pipefail
IMG=/root/r36/out/r36max2-ubuntu-v14.img
losetup -D 2>/dev/null || true
losetup -P -f "$IMG"
L=$(losetup -j "$IMG" | cut -d: -f1)
for _ in $(seq 1 40); do [ -b "${L}p2" ] && break; sleep 0.3; done
echo "loop=$L"
mkdir -p /mnt/v14r /mnt/v14b
mount -o ro "${L}p2" /mnt/v14r
mount -o ro "${L}p1" /mnt/v14b
echo "=== driver in the image ==="
K=/mnt/v14r/usr/lib/modules/6.12.79/extra/aic8800_fdrv.ko
ls -la "$K"
echo "release : $(strings -a "$K" | grep -m1 -E '^20[0-9]{2}_[0-9]{4}')"
echo "h_u02   : $(strings -a "$K" | grep -cE 'h_u02') references"
echo "=== firmware ==="
ls /mnt/v14r/lib/firmware/aic8800DC | grep -cE 'h_u02'
ls /mnt/v14r/lib/firmware/aic8800DC | grep -E 'h_u02' | tr '\n' ' '; echo
echo "=== tools / units ==="
echo "rfkill  : $(ls /mnt/v14r/usr/sbin/rfkill 2>/dev/null || echo MISSING)"
echo "nss     : $(grep '^hosts' /mnt/v14r/etc/nsswitch.conf)"
echo "enabled : $(ls /mnt/v14r/etc/systemd/system/multi-user.target.wants/ | tr '\n' ' ')"
echo "timers  : $(ls /mnt/v14r/etc/systemd/system/timers.target.wants/ | grep r36)"
echo "wpa cfg : $(ls /mnt/v14r/etc/wpa_supplicant/ | tr '\n' ' ')"
echo "=== BOOT partition ==="
ls /mnt/v14b | tr '\n' ' '; echo
echo "boot.ini size: $(stat -c %s /mnt/v14b/boot.ini)  usbhost switch: $(grep -c usbhost /mnt/v14b/boot.ini)"
echo "alt fw dir   : $(ls /mnt/v14b/fw/aic8800DC 2>/dev/null | tr '\n' ' ')"
umount /mnt/v14r /mnt/v14b; losetup -d "$L"
echo "=== V14 VERIFY DONE ==="
