#!/bin/bash
# Rebuild the initramfs: ext4-only probing (kills exFAT noise), verbose progress,
# clean handover (umount proc/sys before switch_root), and a shell fallback that says why.
set -eu
SRC=/root/r36/bs/busybox
IR=/root/r36/initrd
OUT=/root/r36/out/boot

rm -rf "$IR"; mkdir -p "$IR"/{bin,sbin,dev,proc,sys,newroot,etc}
cp "$SRC" "$IR/bin/busybox"
for a in sh mount umount switch_root cat ls grep mkdir sleep dmesg insmod echo test blkid; do
  ln -sf busybox "$IR/bin/$a"
done

cat > "$IR/init" <<'EOF'
#!/bin/sh
# r36max2 initramfs: find the Ubuntu rootfs (ext4 + marker file) on any device.
export PATH=/bin:/sbin
mount -t devtmpfs devtmpfs /dev  2>/dev/null
mount -t proc      proc      /proc 2>/dev/null
mount -t sysfs     sysfs     /sys  2>/dev/null

echo "== r36max2 initrd: cmdline: $(cat /proc/cmdline)"
MARKER=etc/r36max2-build-info
FOUND=""
i=0
while [ "$i" -lt 40 ]; do
    for d in /dev/mmcblk*p* /dev/sda*; do
        [ -b "$d" ] || continue
        if mount -t ext4 -o rw "$d" /newroot 2>/dev/null; then
            if [ -f "/newroot/$MARKER" ]; then FOUND="$d"; break; fi
            umount /newroot 2>/dev/null
        fi
    done
    [ -n "$FOUND" ] && break
    sleep 0.5; i=$((i + 1))
done

if [ -z "$FOUND" ]; then
    echo "== r36max2 initrd: NO rootfs found; devices present:"
    ls -l /dev/ | grep -E "mmcblk|sd"
    echo "== dropping to shell for debugging =="
    exec sh
fi

echo "== r36max2 initrd: rootfs on $FOUND; init: $(ls -l /newroot/sbin/init 2>&1 | tail -1)"
cat /newroot/$MARKER
# hand the API filesystems over cleanly
umount /proc 2>/dev/null; umount /sys 2>/dev/null
exec switch_root /newroot /sbin/init
echo "== r36max2 initrd: switch_root RETURNED (failure); starting shell =="
exec sh
EOF
chmod +x "$IR/init"

cd "$IR"
find . | cpio -o -H newc --quiet 2>/dev/null | gzip -9 > /tmp/initrd.cpio.gz
mkimage -A arm64 -O linux -T ramdisk -C gzip -n "uInitrd-r36max2" -d /tmp/initrd.cpio.gz "$OUT/uInitrd" >/dev/null
echo "uInitrd: $(ls -l "$OUT/uInitrd" | awk '{print $5}') bytes"
gzip -dc /tmp/initrd.cpio.gz | cpio -t --quiet 2>/dev/null | grep -E "^init$|bin/switch_root|bin/mount"
