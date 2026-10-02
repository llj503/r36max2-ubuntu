#!/bin/bash
set -uo pipefail
R=/root/r36/rootfs
echo "=== the h_u02 firmware we need to ship ==="
ls -la "$R/lib/firmware/aic8800DC/" | grep -E 'h_u02|u02h'
echo "=== regulatory.db ==="
ls -la "$R/lib/firmware/regulatory.db" 2>/dev/null || echo "MISSING regulatory.db"
dpkg -s wireless-regdb 2>/dev/null | grep -E '^(Status|Version)' || echo "wireless-regdb not installed"
echo "=== what pulls regulatory.db? kernel requests /lib/firmware/regulatory.db ==="
ls "$R/usr/lib/firmware/" 2>/dev/null | head
echo "=== rfkill package ==="
chroot "$R" /bin/sh -c 'command -v rfkill || echo "no rfkill binary"'
echo "=== nss-mdns? ==="
grep -E 'hosts' "$R/etc/nsswitch.conf"
