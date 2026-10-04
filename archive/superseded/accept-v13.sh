#!/bin/bash
# Acceptance check of v13: the new driver, its firmware, and the small fixes.
set -uo pipefail
IMG=/root/r36/out/r36max2-ubuntu-v13.img
losetup -D 2>/dev/null || true
losetup -P -f "$IMG"; L=$(losetup -j "$IMG" | cut -d: -f1)
for _ in $(seq 1 40); do [ -b "${L}p1" ] && [ -b "${L}p2" ] && break; sleep 0.3; done
mkdir -p /mnt/v13b /mnt/v13r
mount -o ro "${L}p1" /mnt/v13b; mount -o ro "${L}p2" /mnt/v13r
X=/mnt/v13r/usr/lib/modules/6.12.79/extra

echo "=== modules in the image ==="
ls -la $X | tail -6
echo "  fdrv vermagic : $(modinfo -F vermagic $X/aic8800_fdrv.ko)"
echo "  fw release    : $(strings -a $X/aic8800_fdrv.ko | grep -m1 -E '^20[0-9]{2}_[0-9]{4}')"
echo "  h_u02 refs    : $(strings -a $X/aic8800_fdrv.ko | grep -cE 'h_u02') (expect 5+: patch, tbl, calib + logs)"
echo "  calib code    : $(strings -a $X/aic8800_fdrv.ko | grep -m1 fmacfw_calib_8800dc_h_u02.bin)"

echo "=== firmware the chip needs ==="
ls /mnt/v13r/lib/firmware/aic8800DC/ | grep -E 'h_u02' | tr '\n' ' '; echo
echo "  regulatory.db : $(stat -c %s /mnt/v13r/lib/firmware/regulatory.db 2>/dev/null) bytes"

echo "=== tools / units ==="
echo "  rfkill        : $(ls /mnt/v13r/usr/sbin/rfkill 2>/dev/null || echo MISSING)"
echo "  nsswitch      : $(grep '^hosts' /mnt/v13r/etc/nsswitch.conf)"
echo "  wpa drop-in   : $(sed -n '/ExecStartPre/p;/Restart=/p' /mnt/v13r/etc/systemd/system/wpa_supplicant-nl80211@.service.d/r36.conf | tr '\n' ' ')"
echo "  enabled units : $(ls /mnt/v13r/etc/systemd/system/multi-user.target.wants/ | tr '\n' ' ')"
echo "  timers        : $(ls /mnt/v13r/etc/systemd/system/timers.target.wants/ | grep r36)"
echo "  unit perms    : $(stat -c '%a %n' /mnt/v13r/etc/systemd/system/r36-bootlog.timer /mnt/v13r/etc/systemd/system/r36-bootlog.service | tr '\n' '; ')"
echo "  bootlog mount : $(grep -m1 'mount -t vfat' /mnt/v13r/usr/local/sbin/r36-bootlog)"
echo "  bootlog osrel : $(grep -m1 'PRETTY_NAME' /mnt/v13r/usr/local/sbin/r36-bootlog | cut -c1-60)"
echo "  build info    : $(cat /mnt/v13r/etc/r36max2-build-info)"
echo "  wpa conf      : $(ls -la /mnt/v13r/etc/wpa_supplicant/wpa_supplicant-nl80211-wlan0.conf | awk '{print $1, $5}')"

echo "=== boot partition ==="
ls /mnt/v13b | tr '\n' ' '; echo
head -1 /mnt/v13b/boot.ini; grep -c usbhost /mnt/v13b/boot.ini
umount /mnt/v13b /mnt/v13r; losetup -d "$L"
echo "=== sizes ==="
ls -la /mnt/e/ubuntu/out/r36max2-ubuntu-v13.img.xz
echo "=== DONE ==="
