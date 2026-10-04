#!/bin/bash
# v20-apt-fix.sh - apply-wayland.sh found no weston/foot/wofi because the lists
# were wiped by apply-v19.sh's cleanup (rm -rf /var/lib/apt/lists/*) and the
# update in the chroot did not repopulate them.  See the actual error instead of
# trusting a "|| echo noisy".
set -uo pipefail
R=/root/r36/rootfs
WSLNS=$(awk '/^nameserver/{print $2; exit}' /etc/resolv.conf)

mount -t proc proc "$R/proc" 2>/dev/null || true
cp -f /etc/resolv.conf "$R/etc/resolv.conf.tmp" 2>/dev/null
printf 'nameserver %s\n' "$WSLNS" > "$R/etc/resolv.conf"
echo "  chroot resolver: $(grep '^nameserver' "$R/etc/resolv.conf" | tr '\n' ' ')   (host used: $WSLNS)"
echo "  lists dir: $(ls "$R/var/lib/apt/lists" 2>/dev/null | wc -l) files"
echo "  sources:"
grep -rhE "^(deb|deb-src)" "$R/etc/apt/sources.list" "$R/etc/apt/sources.list.d/" 2>/dev/null | head -5 | sed 's/^/    /'

echo
echo "=== can the chroot reach the archive? ==="
chroot "$R" /usr/bin/env getent hosts ports.ubuntu.com 2>&1 | head -2 | sed 's/^/  dns: /'
chroot "$R" /usr/bin/env apt-get update 2>&1 | tail -12 | sed 's/^/  /'
echo "  lists now: $(ls "$R/var/lib/apt/lists" 2>/dev/null | grep -c _Packages)"

echo
echo "=== does apt now know the packages? ==="
for p in weston wayland-protocols libwayland-dev grim wf-recorder foot wofi kbd; do
  c=$(chroot "$R" apt-cache policy "$p" 2>/dev/null | awk '/Candidate:/{print $2}')
  printf "  %-18s %s\n" "$p" "${c:-none}"
done
