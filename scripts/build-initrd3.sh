#!/bin/bash
# Regenerate the initramfs: ext4-only probe, verbose, backlight kick, clean handover.
set -eu
SRC=/root/r36/bs/busybox
IR=/root/r36/initrd
OUT=/root/r36/out/boot

rm -rf "$IR"; mkdir -p "$IR"/{bin,sbin,dev,proc,sys,newroot,etc}
cp "$SRC" "$IR/bin/busybox"
for a in sh mount umount switch_root cat ls grep mkdir sleep dmesg insmod echo test; do
  ln -sf busybox "$IR/bin/$a"
done

cat > "$IR/init" <<'EOF'
#!/bin/sh
# r36max2 initramfs: locate the Ubuntu rootfs (ext4 + marker) on any device, keep the
# panel lit, then hand over to systemd.
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

if [ -n "$FOUND" ]; then
    echo "== r36max2 initrd: rootfs on $FOUND"
    cat "/newroot/$MARKER"
else
    echo "== r36max2 initrd: rootfs NOT found; block devices:"
    ls -l /dev/ | grep -E "mmcblk|sd[a-z]"
    echo "== dropping to shell =="
    exec sh
fi

# A handheld whose PWM backlight lands on 0 during the DRM handover looks identical to a
# hung system, so force it to max before we leave the initramfs.
for b in /sys/class/backlight/*; do
    [ -w "$b/brightness" ] || continue
    m=$(cat "$b/max_brightness" 2>/dev/null || echo 255)
    echo "$m" > "$b/brightness" 2>/dev/null && echo "== r36max2 initrd: $(basename $b) -> $m"
done

umount /proc 2>/dev/null; umount /sys 2>/dev/null
exec switch_root /newroot /sbin/init
echo "== r36max2 initrd: switch_root RETURNED (failure) =="
exec sh
EOF
chmod +x "$IR/init"

mkdir -p "$OUT"
cp -f /root/r36/linux-6.12.79/arch/arm64/boot/Image "$OUT/Image"
cp -f /root/r36/linux-6.12.79/arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dtb "$OUT/"
cd "$IR"
find . | cpio -o -H newc --quiet 2>/dev/null | gzip -9 > /tmp/initrd.cpio.gz
mkimage -A arm64 -O linux -T ramdisk -C gzip -n "uInitrd-r36max2" -d /tmp/initrd.cpio.gz "$OUT/uInitrd" >/dev/null
ls -la "$OUT"
gzip -dc /tmp/initrd.cpio.gz | cpio -t --quiet 2>/dev/null | grep -E "^init$|bin/busybox"
