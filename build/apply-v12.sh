#!/bin/bash
# v12 = v11 + status printed on screen + a BOOT-file switch for the USB-host dtb.
set -eu
R=/root/r36/rootfs
SRC=/mnt/e/ubuntu/build
OUT=/root/r36/out
K=/root/r36/linux-6.12.79
D=$K/arch/arm64/boot/dts/rockchip

cp -f "$SRC/r36-bootlog" "$R/usr/local/sbin/r36-bootlog"
chmod 755 "$R/usr/local/sbin/r36-bootlog"
sh -n "$R/usr/local/sbin/r36-bootlog" && echo "bootlog script parses ok"
grep -c 'dev/console' "$R/usr/local/sbin/r36-bootlog"

# make the alternate dtb available to the staging dir the pack script uses
cp -f "$D/rk3326-xifan-r36max2-usbhost.dtb" "$OUT/boot/"
ls -la "$OUT/boot"

V=v12 bash "$SRC/pack-v10.sh" 2>&1 | tail -14
