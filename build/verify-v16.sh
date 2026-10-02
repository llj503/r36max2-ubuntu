#!/bin/bash
set -uo pipefail
I=/root/r36/out/r36max2-ubuntu-v16.img
losetup -D 2>/dev/null || true
losetup -P -f "$I"
L=$(losetup -j "$I" | cut -d: -f1)
for _ in $(seq 1 40); do [ -b "${L}p1" ] && [ -b "${L}p2" ] && break; sleep 0.3; done
mkdir -p /mnt/v16b /mnt/v16r
mount -o ro "${L}p1" /mnt/v16b
mount -o ro "${L}p2" /mnt/v16r
echo "=== udev present in the shipped image? ==="
ls -l /mnt/v16r/usr/lib/systemd/systemd-udevd
echo "sysinit wants : $(ls /mnt/v16r/etc/systemd/system/sysinit.target.wants/ | grep -i udev | tr '\n' ' ')"
echo "sockets wants : $(ls /mnt/v16r/etc/systemd/system/sockets.target.wants/ | grep -i udev | tr '\n' ' ')"
echo "rules         : $(ls /mnt/v16r/usr/lib/udev/rules.d/ | wc -l) files"
echo "=== wifi stack ==="
echo "driver        : $(strings -a /mnt/v16r/usr/lib/modules/6.12.79/extra/aic8800_fdrv.ko | grep -m1 -E '^20[0-9]{2}_[0-9]{4}')"
echo "h_u02 fw      : $(ls /mnt/v16r/lib/firmware/aic8800DC | grep -c h_u02) files"
echo "wpa enabled   : $(ls /mnt/v16r/etc/systemd/system/multi-user.target.wants/ | grep -iE 'wpa' | tr '\n' ' ')"
echo "wpa unit      : $(grep -E 'ExecStart=|Restart=' /mnt/v16r/etc/systemd/system/r36-wpa@.service | tr '\n' '|')"
echo "wpa config    : $(ls /mnt/v16r/etc/wpa_supplicant/ | tr '\n' ' ')"
echo "resolv.conf   : $(grep -c nameserver /mnt/v16r/etc/resolv.conf) servers: $(awk '/nameserver/{printf "%s ",$2}' /mnt/v16r/etc/resolv.conf)"
echo "networkd prof : $(ls /mnt/v16r/etc/systemd/network/ | tr '\n' ' ')"
echo "=== screen page ==="
grep -c 'chvt' /mnt/v16r/usr/local/sbin/r36-status-screen
grep -n 'dev/console' /mnt/v16r/usr/local/sbin/r36-status-screen | head -3
grep -n 'networking services' /mnt/v16r/usr/local/sbin/r36-bootlog
echo "=== boot partition ==="
ls /mnt/v16b | tr '\n' ' '; echo
echo "boot.ini \${dtb}: $(grep -c '{dtb}' /mnt/v16b/boot.ini)"
umount /mnt/v16b /mnt/v16r; losetup -d "$L"
ls -la /mnt/e/ubuntu/out/r36max2-ubuntu-v16.img.xz*
echo "=== V16 VERIFY DONE ==="
