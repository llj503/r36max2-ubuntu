#!/bin/bash
# Build a minimal but robust initramfs (static busybox) that finds the Ubuntu rootfs
# by marker file, so booting never depends on mmcblk numbering or kernel UUID support.
set -eu
SRC=/root/r36/bs/busybox
IR=/root/r36/initrd
OUT=/root/r36/out/boot

rm -rf "$IR"; mkdir -p "$IR"/{bin,sbin,dev,proc,sys,newroot,etc}
cp "$SRC" "$IR/bin/busybox"
for a in sh mount umount switch_root cat ls grep mkdir sleep dmesg insmod echo test [; do
  ln -sf busybox "$IR/bin/$a"
done

cat > "$IR/init" <<'EOF'
#!/bin/sh
# Tiny initramfs: locate the Ubuntu rootfs (marked by /etc/r36max2-build-info) on any
# block device, mount it read-write and hand over to systemd. Avoids depending on
# mmcblk enumeration order or kernel-side root=UUID= support (which mainline lacks).
export PATH=/bin:/sbin
mount -t devtmpfs devtmpfs /dev  2>/dev/null
mount -t proc      proc      /proc 2>/dev/null
mount -t sysfs     sysfs     /sys  2>/dev/null

MARKER=etc/r36max2-build-info
i=0
while [ "$i" -lt 120 ]; do
    for d in /dev/mmcblk*p* /dev/sda* /dev/mmcblk*p; do
        [ -b "$d" ] || continue
        if mount -o rw "$d" /newroot 2>/dev/null; then
            if [ -f "/newroot/$MARKER" ]; then
                echo "r36max2 initrd: rootfs found on $d"
                exec switch_root /newroot /sbin/init "$@"
            fi
            umount /newroot 2>/dev/null
        fi
    done
    sleep 0.5
    i=$((i + 1))
done

echo "r36max2 initrd: FAILED to find rootfs; dropping to shell"
dmesg | tail -40
exec sh
EOF
chmod +x "$IR/init"

mkdir -p "$OUT"
cp -f /root/r36/linux-6.12.79/arch/arm64/boot/Image "$OUT/Image"
cp -f /root/r36/linux-6.12.79/arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dtb "$OUT/"

cd "$IR"
find . | cpio -o -H newc --quiet 2>/dev/null | gzip -9 > /tmp/initrd.cpio.gz
mkimage -A arm64 -O linux -T ramdisk -C gzip -n "uInitrd-r36max2" -d /tmp/initrd.cpio.gz "$OUT/uInitrd" >/dev/null

echo "=== initramfs built ==="
ls -la "$OUT"
echo "uncompressed size: $(gzip -dc /tmp/initrd.cpio.gz | wc -c) bytes"
echo "=== sanity: /init present at archive root? ==="
gzip -dc /tmp/initrd.cpio.gz | cpio -tv --quiet 2>/dev/null | head -6
