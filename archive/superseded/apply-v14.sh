#!/bin/bash
# v14 = v13 + a persistent status page on tty3 (nothing scrolls away any more).
set -eu
R=/root/r36/rootfs
SRC=/mnt/e/ubuntu/build

cp -f "$SRC/r36-status-screen" "$R/usr/local/sbin/r36-status-screen"
chmod 755 "$R/usr/local/sbin/r36-status-screen"
cp -f "$SRC/r36-status-screen.service" "$R/etc/systemd/system/r36-status-screen.service"
chmod 644 "$R/etc/systemd/system/r36-status-screen.service"
mkdir -p "$R/etc/systemd/system/multi-user.target.wants"
ln -sf /etc/systemd/system/r36-status-screen.service "$R/etc/systemd/system/multi-user.target.wants/r36-status-screen.service"
sh -n "$R/usr/local/sbin/r36-status-screen" && echo "status screen parses ok"
ls -l "$R/usr/local/sbin/" | awk '{print $1, $NF}'
echo "  enabled: $(ls "$R/etc/systemd/system/multi-user.target.wants/" | tr '\n' ' ')"
V=v14 bash "$SRC/pack-v10.sh" 2>&1 | tail -12
