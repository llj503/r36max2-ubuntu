#!/bin/bash
# Why is there no /sbin/init? ubuntu-base ships WITHOUT systemd-sysv, and the base image
# itself has no init at all; openssh-server pulls in `systemd` but NOT the /sbin/init symlink.
set -u
ROOT=/root/r36/rootfs
echo "=== init candidates in the rootfs ==="
for p in sbin/init usr/sbin/init lib/systemd/systemd usr/lib/systemd/systemd bin/sh; do
  printf "  %-28s " "/$p"; [ -e "$ROOT/$p" ] && echo "EXISTS ($(readlink -f "$ROOT/$p" 2>/dev/null | sed "s|$ROOT||"))" || echo MISSING
done
echo "=== is systemd installed? ==="
chroot "$ROOT" /bin/sh -c 'dpkg -l | grep -E "^i. +(systemd|systemd-sysv|dbus|avahi-daemon|wireless-regdb) " ' 2>/dev/null || echo "(dpkg query failed)"
echo "=== /etc/systemd/system/*.wants (what we enabled) ==="
ls "$ROOT/etc/systemd/system/multi-user.target.wants/" 2>/dev/null
