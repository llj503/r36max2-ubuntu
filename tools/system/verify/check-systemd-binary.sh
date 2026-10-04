#!/bin/bash
# Is the systemd in the rootfs real? (133 KB looks like a truncated extract)
set -uo pipefail
R=/root/r36/rootfs
echo "=== file/size ==="
ls -la "$R"/lib/systemd/systemd* "$R"/usr/lib/systemd/systemd 2>/dev/null | head
file "$R/usr/lib/systemd/systemd" 2>/dev/null
echo "=== dpkg status of the core packages ==="
grep -A1 '^Package: \(systemd\|systemd-sysv\|udev\|dbus\|openssh-server\|wpasupplicant\|avahi-daemon\|networkd-dispatcher\)$' "$R/var/lib/dpkg/status" | grep -E '^(Package|Status|Version)' | tr '\n' ' ' | sed 's/Status: install ok installed/\n/g'
echo
echo "=== dpkg --verify (missing/modified files) ==="
chroot "$R" /usr/bin/env dpkg -V systemd 2>&1 | head -20
echo "--- verify count for a few packages ---"
for p in systemd udev dbus openssh-server wpasupplicant; do
  n=$(chroot "$R" /usr/bin/env dpkg -V "$p" 2>/dev/null | wc -l)
  echo "$p: $n mismatches"
done
echo "=== dpkg -L systemd | head ==="
chroot "$R" /usr/bin/env dpkg -L systemd 2>/dev/null | head -8
echo "=== can qemu run it? ==="
chroot "$R" /usr/bin/env /lib/systemd/systemd --version 2>&1 | head -3
