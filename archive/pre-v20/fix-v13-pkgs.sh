#!/bin/bash
set -uo pipefail
R=/root/r36/rootfs
WSLNS=$(awk '/^nameserver/{print $2; exit}' /etc/resolv.conf)
mount -t proc proc "$R/proc" 2>/dev/null || true
printf 'nameserver %s\n' "$WSLNS" > "$R/etc/resolv.conf"
echo "=== apt update (show errors this time) ==="
chroot "$R" /usr/bin/env apt-get update 2>&1 | tail -5
echo "=== candidates ==="
for p in rfkill nss-mdns libnss-mdns wireless-regdb wpagui; do
  echo "-- $p"; chroot "$R" /usr/bin/env apt-cache policy "$p" 2>/dev/null | sed -n '1,3p'
done
echo "=== where is regulatory.db really? ==="
chroot "$R" /bin/sh -c 'ls -la /usr/lib/firmware/regulatory* /lib/firmware/regulatory* 2>/dev/null; dpkg -L wireless-regdb | grep -v dir'
echo "=== install what exists ==="
chroot "$R" /usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -y install rfkill 2>&1 | tail -3
chroot "$R" /usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -y install libnss-mdns 2>&1 | tail -3
ls -l "$R/usr/sbin/rfkill" 2>/dev/null || echo "rfkill still absent"
grep '^hosts' "$R/etc/nsswitch.conf"
umount -f "$R/proc" 2>/dev/null || true
chroot "$R" /usr/bin/env apt-get clean; rm -rf "$R"/var/lib/apt/lists/*
du -sk "$R" | awk '{printf "rootfs: %.2f GiB\n", $1/1048576}'
