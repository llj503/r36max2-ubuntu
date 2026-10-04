#!/bin/bash
# v15 = fix the boot.ini I broke (variable dtb name -> "dtb load fail" -> black
# screen), plus a defensive status page and a quieter console.
set -eu
R=/root/r36/rootfs
SRC=/mnt/e/ubuntu/build

cp -f "$SRC/r36-bootlog"        "$R/usr/local/sbin/r36-bootlog"
cp -f "$SRC/r36-status-screen"  "$R/usr/local/sbin/r36-status-screen"
chmod 755 "$R/usr/local/sbin/r36-bootlog" "$R/usr/local/sbin/r36-status-screen"
sh -n "$R/usr/local/sbin/r36-bootlog" && sh -n "$R/usr/local/sbin/r36-status-screen" && echo "scripts parse ok"
grep -c 'noscreen' "$R/usr/local/sbin/r36-status-screen"

echo "=== a getty on tty3 as the anti-black-screen net ==="
mkdir -p "$R/etc/systemd/system/getty.target.wants"
ln -sf /lib/systemd/system/getty@.service "$R/etc/systemd/system/getty.target.wants/getty@tty3.service"
ls -l "$R/etc/systemd/system/getty.target.wants/"

echo "=== pack v15 ==="
V=v15 bash "$SRC/pack-v10.sh" 2>&1 | tail -12
