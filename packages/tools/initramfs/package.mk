# SPDX-License-Identifier: GPL-2.0-or-later
# initramfs: the uInitrd handed to booti. Locates the Ubuntu rootfs (ext4 +
# etc/r36max2-build-info marker) on any block device, keeps the panel lit,
# hands over to systemd. Assembled reproducibly: sorted entries, clamped
# mtimes (cpio --reproducible).

PKG_NAME="initramfs"
PKG_VERSION="1.0"
PKG_LICENSE="GPL-2.0-or-later"
PKG_SITE="https://github.com/llj503/r36max2-ubuntu"
PKG_URL=""
PKG_DEPENDS_TARGET="busybox"
PKG_LONGDESC="uInitrd: rootfs probe + backlight kick + switch_root."
PKG_TOOLCHAIN="manual"

make_target() {
  :
}

makeinstall_target() {
  local IR="${PKG_BUILD}/.initramfs"
  rm -rf "${IR}"
  mkdir -p ${IR}/{bin,sbin,dev,proc,sys,newroot,etc}
  cp $(get_build_dir busybox)/busybox ${IR}/bin/busybox
  chmod 755 ${IR}/bin/busybox
  for a in sh mount umount switch_root cat ls grep mkdir sleep dmesg insmod echo test; do
    ln -sf busybox ${IR}/bin/$a
  done

  cat > ${IR}/init <<'EOF'
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
  chmod 755 ${IR}/init

  # The archive built below is gzip, so the kernel has to be able to decompress gzip.
  # The inherited rocknix template enables RD_LZO only, and the first v21 card booted to
  # "compression method gzip not configured / Initramfs unpacking failed" and then
  # reset in a loop - with the panel already up, so that message was the whole boot.
  local KCONF="${BUILD}/build/linux-$(get_pkg_version linux)/.config"
  grep -qx 'CONFIG_RD_GZIP=y' "${KCONF}" 2>/dev/null ||
    die "initramfs: kernel has no gzip decompressor (${KCONF}) - the board cannot unpack this initrd"

  # deterministic archive: sorted entries, mtimes clamped to SOURCE_DATE_EPOCH
  mkdir -p ${INSTALL}/.image
  ( cd ${IR} && find . | LC_ALL=C sort | \
      cpio --reproducible -o -H newc --quiet 2>/dev/null ) | gzip -9n \
    > ${PKG_BUILD}/initrd.cpio.gz
  mkimage -A arm64 -O linux -T ramdisk -C gzip -n "uInitrd-r36max2" \
    -d ${PKG_BUILD}/initrd.cpio.gz ${INSTALL}/.image/uInitrd >/dev/null
  # Image/dtb are NOT staged here: scripts/image copies them straight from the
  # linux package's install dir, so what boots is what the modules were built for.
  gzip -dc ${PKG_BUILD}/initrd.cpio.gz | cpio -t --quiet 2>/dev/null | grep -qE "^init$" \
    || die "initramfs: init missing from the archive"
  gzip -dc ${PKG_BUILD}/initrd.cpio.gz | cpio -t --quiet 2>/dev/null | grep -qE "bin/busybox" \
    || die "initramfs: busybox missing from the archive"
}
