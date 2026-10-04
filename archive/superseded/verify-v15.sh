#!/bin/bash
set -uo pipefail
I=/root/r36/out/r36max2-ubuntu-v15.img
losetup -D 2>/dev/null || true
losetup -P -f "$I"
L=$(losetup -j "$I" | cut -d: -f1)
for _ in $(seq 1 40); do [ -b "${L}p1" ] && [ -b "${L}p2" ] && break; sleep 0.3; done
mkdir -p /mnt/v15b /mnt/v15r
mount -o ro "${L}p1" /mnt/v15b
mount -o ro "${L}p2" /mnt/v15r
echo "=== FAT ==="
ls /mnt/v15b | tr '\n' ' '; echo
echo "boot.ini bytes: $(stat -c %s /mnt/v15b/boot.ini)   \${dtb} occurrences: $(grep -c '{dtb}' /mnt/v15b/boot.ini)"
echo "dtb load line : $(grep 'load mmc 1:1 \${dtb_loadaddr}' /mnt/v15b/boot.ini)"
echo "bootargs      : $(grep -m1 bootargs /mnt/v15b/boot.ini)"
echo "=== rootfs ==="
echo "driver release: $(strings -a /mnt/v15r/usr/lib/modules/6.12.79/extra/aic8800_fdrv.ko | grep -m1 -E '^20[0-9]{2}_[0-9]{4}')"
echo "getty wants   : $(ls /mnt/v15r/etc/systemd/system/getty.target.wants/ | tr '\n' ' ')"
echo "screen script : $(grep -c noscreen /mnt/v15r/usr/local/sbin/r36-status-screen) noscreen guards"
echo "bootlog console writes: $(grep -c 'dev/console' /mnt/v15r/usr/local/sbin/r36-bootlog)"
echo "enabled       : $(ls /mnt/v15r/etc/systemd/system/multi-user.target.wants/ | tr '\n' ' ')"
umount /mnt/v15b /mnt/v15r
losetup -d "$L"
ls -la /mnt/e/ubuntu/out/r36max2-ubuntu-v15.img.xz*
echo "=== V15 VERIFY DONE ==="
