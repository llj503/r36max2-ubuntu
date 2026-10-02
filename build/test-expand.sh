#!/bin/bash
# Full test of the expand script against a 4 GiB copy of the current v10 image.
set -uo pipefail
IMG=/root/r36/out/r36max2-ubuntu-v10.img
SRC=/mnt/e/ubuntu/build
B=/tmp/v10dry.bin

cp -f "$SRC/r36-expand-root" /tmp/x.sh; chmod +x /tmp/x.sh
rm -f "$B"; cp --sparse=always "$IMG" "$B"; truncate -s 4G "$B"
losetup -D 2>/dev/null || true
losetup -P -f "$B"; D=$(losetup -j "$B" | cut -d: -f1); DD=${D#/dev/}
for _ in $(seq 1 40); do [ -b "${D}p2" ] && break; sleep 0.3; done
mkdir -p /mnt/v10root
mount "${D}p2" /mnt/v10root
sed -i "s#^ROOT=.*#ROOT=/dev/${DD}p2#; s#^MARK=.*#MARK=/mnt/v10root/var/lib/r36-expand-pending#" /tmp/x.sh
echo "--- before: disk=$(blockdev --getsz "$D") p2=$(blockdev --getsz "${D}p2") sectors ---"
/tmp/x.sh
echo "rc=$?"
echo "--- after : disk=$(blockdev --getsz "$D") p2=$(blockdev --getsz "${D}p2") sectors ---"
sfdisk -d "$D"
df -h /mnt/v10root | tail -1
[ -e /mnt/v10root/var/lib/r36-expand-pending ] && echo "MARKER PRESENT (finisher would run at next boot)" || echo "no marker"
umount /mnt/v10root; losetup -d "$D"; rm -f "$B"
echo "=== EXPAND TEST DONE ==="
