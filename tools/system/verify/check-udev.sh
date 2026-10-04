#!/bin/bash
# Is the udev package (and thus systemd-udevd + device units) present?
set -uo pipefail
R=/root/r36/rootfs
echo "=== dpkg: systemd / udev / networkd related ==="
grep -A1 -E '^Package: (systemd|udev|systemd-udev|ifupdown|networkd-dispatcher|wireless-regdb|rfkill)$' "$R/var/lib/dpkg/status" | grep -E '^(Package|Version|Status)' | paste - - - | sed 's/Status: install ok installed//'
echo "=== udevd binary + units in the rootfs ==="
ls -la "$R/lib/systemd/systemd-udevd" "$R/usr/lib/systemd/systemd-udevd" 2>/dev/null || echo "  NO systemd-udevd binary"
ls "$R/lib/systemd/system/" | grep -i udev || echo "  no udev units"
echo "=== sockets.target.wants (udevd sockets live here) ==="
ls "$R/etc/systemd/system/sockets.target.wants/" 2>/dev/null || echo "  (no sockets.target.wants)"
echo "=== is udev-trigger there? ==="
ls "$R/lib/systemd/system/" 2>/dev/null | grep -E 'udev|networkd' | tr '\n' ' '; echo
echo "=== /etc/udev rules dir ==="
ls "$R/etc/udev/rules.d/" 2>/dev/null | head; ls "$R/lib/udev/rules.d/" 2>/dev/null | wc -l
echo "=== networkd units enabled? ==="
ls -l "$R/etc/systemd/system/multi-user.target.wants/" | grep -i network || echo "  networkd NOT in multi-user.wants"
echo "=== what does report say about failed units (v15) ==="
sed -n '/failed units/,/interfaces/p' /mnt/e/ubuntu/logs/r36-boot-20261001-192621.txt
