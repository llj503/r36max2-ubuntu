#!/bin/bash
# v13 (final): + the BOOT-partition firmware override escape hatch.
set -eu
R=/root/r36/rootfs
SRC=/mnt/e/ubuntu/build

cp -f "$SRC/r36-fwswap" "$R/usr/local/sbin/r36-fwswap"
chmod 755 "$R/usr/local/sbin/r36-fwswap"
cp -f "$SRC/r36-fwswap.service" "$R/etc/systemd/system/r36-fwswap.service"
chmod 644 "$R/etc/systemd/system/r36-fwswap.service"
mkdir -p "$R/etc/systemd/system/multi-user.target.wants"
ln -sf /etc/systemd/system/r36-fwswap.service "$R/etc/systemd/system/multi-user.target.wants/r36-fwswap.service"
sh -n "$R/usr/local/sbin/r36-fwswap" && echo "fwswap parses ok"
ls -l "$R/usr/local/sbin/" | awk '{print $1, $NF}'
V=v13 bash "$SRC/pack-v10.sh" 2>&1 | tail -12
