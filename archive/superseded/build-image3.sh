#!/bin/bash
# v3 image. Evidence-driven: the device's u-boot (U-Boot 2017.09-g05bceb2) runs
#   bootcmd -> distro_bootcmd with boot_targets="mmc1 mmc0 ..."   (mmc1 = SD, checked first)
#   scan_dev_for_boot -> scan_dev_for_extlinux (looks for <prefix>extlinux/extlinux.conf)
#                      -> scan_dev_for_scripts (boot.scr / boot.cmd ...)
# It does NOT validate a "boot.ini" magic (that is ArkOS's own u-boot feature).
# So the authoritative entry point is extlinux/extlinux.conf; boot.scr and boot.ini
# are kept as extra fallbacks. p1 is also marked bootable so `-bootable devplist` finds it.
set -eu
OUT=/root/r36/out
IMG="$OUT/r36max2-ubuntu-v3.img"
ROOT=/root/r36/rootfs
BOOT_SRC="$OUT/boot"
BLOBS=/mnt/e/ubuntu/artifacts
IMG_GB=${1:-58}

rm -f "$IMG"; truncate -s "${IMG_GB}G" "$IMG"
printf 'label: dos\nunit: sectors\n\nstart=32768, size=1048576, type=c, bootable\nstart=1081344, type=83\n' > /tmp/pt3
sfdisk -q "$IMG" < /tmp/pt3

dd if="$BLOBS/idbloader.img" of="$IMG" bs=512 seek=64    conv=notrunc,fsync status=none
dd if="$BLOBS/uboot.img"     of="$IMG" bs=512 seek=16384 conv=notrunc,fsync status=none
dd if="$BLOBS/trust.img"     of="$IMG" bs=512 seek=24576 conv=notrunc,fsync status=none

losetup -P -f "$IMG"
LOOP=$(losetup -j "$IMG" | cut -d: -f1)
for i in 1 2; do for _ in $(seq 1 30); do [ -b "${LOOP}p$i" ] && break; sleep 0.4; done; done
mkfs.vfat -F 32 -n BOOT "${LOOP}p1" >/dev/null
mkfs.ext4 -q -L UBUNTU "${LOOP}p2"
UUID=$(blkid -s UUID -o value "${LOOP}p2")
echo "rootfs UUID=$UUID"

MNT=/mnt/r36v3
rm -rf "$MNT"; mkdir -p "$MNT/boot" "$MNT/root"
mount "${LOOP}p1" "$MNT/boot"; mount "${LOOP}p2" "$MNT/root"
mkdir -p "$MNT/boot/extlinux"

cp "$BOOT_SRC/Image" "$MNT/boot/Image"; cp "$BOOT_SRC/Image" "$MNT/boot/KERNEL"
cp "$BOOT_SRC/rk3326-xifan-r36max2.dtb" "$MNT/boot/"
cp "$BOOT_SRC/rk3326-xifan-r36max2.dtb" "$MNT/boot/rk3326-evb-lp3-v12-linux.dtb"
cp "$BOOT_SRC/rk3326-xifan-r36max2.dtb" "$MNT/boot/rk3326-r36max2-linux.dtb"

# --- primary entry point for this u-boot ---
cat > "$MNT/boot/extlinux/extlinux.conf" <<ELX
LABEL Ubuntu
  LINUX /Image
  FDT /rk3326-xifan-r36max2.dtb
  APPEND root=UUID=$UUID rootwait rw net.ifnames=0 fbcon=rotate:0 console=tty0 quiet loglevel=3
ELX
# names the vendor/ArkOS scripts may look for
cp "$MNT/boot/extlinux/extlinux.conf" "$MNT/boot/extlinux/rk3326-evb-lp3-v12-linux.dtb.conf"
cp "$MNT/boot/extlinux/extlinux.conf" "$MNT/boot/extlinux/rk3326-odroidgo2-linux.dtb.conf"

# --- secondary: boot.scr (scan_dev_for_scripts) ---
# An empty initrd is loaded so `booti` gets the same 3-argument form ArkOS proves works
# on this board; with no /init inside, the kernel still mounts the real root.
printf '' | cpio -o -H newc 2>/dev/null | gzip -9 > "$MNT/boot/empty.cpio.gz"
cat > /tmp/boot3.cmd <<CMD
setenv bootargs "root=UUID=$UUID rootwait rw net.ifnames=0 fbcon=rotate:0 console=tty0 quiet loglevel=3"
fatload mmc 1:1 0x02000000 Image
fatload mmc 1:1 0x01100000 empty.cpio.gz
fatload mmc 1:1 0x01f00000 rk3326-xifan-r36max2.dtb
booti 0x02000000 0x01100000 0x01f00000
CMD
mkimage -T script -C none -A arm64 -n "Ubuntu R36Max2" -d /tmp/boot3.cmd "$MNT/boot/boot.scr"

# --- tertiary: boot.ini (used by ArkOS-style u-boots / manual run) ---
cat > "$MNT/boot/boot.ini" <<INI
ODROIDGOA-UBOOT-CONFIG

setenv bootargs "root=UUID=$UUID rootwait rw net.ifnames=0 fbcon=rotate:0 console=tty0 quiet loglevel=3"
setenv loadaddr "0x02000000"
setenv initrd_loadaddr "0x01100000"
setenv dtb_loadaddr "0x01f00000"

if load mmc 1:1 \${loadaddr} Image; then
  setenv bootdev 1
elif load mmc 0:1 \${loadaddr} Image; then
  setenv bootdev 0
fi

load mmc \${bootdev}:1 \${initrd_loadaddr} empty.cpio.gz
load mmc \${bootdev}:1 \${dtb_loadaddr} rk3326-xifan-r36max2.dtb
booti \${loadaddr} \${initrd_loadaddr} \${dtb_loadaddr}
INI

rsync -aHAX "$ROOT/" "$MNT/root/"
mkdir -p "$MNT/root/proc" "$MNT/root/sys" "$MNT/root/dev" "$MNT/root/run" "$MNT/root/boot"
echo "kernel=6.12.79 entry=extlinux root_uuid=$UUID built=$(date -Is)" > "$MNT/root/etc/r36max2-build-info"

sync; umount "$MNT/root"; umount "$MNT/boot"
e2fsck -fy "${LOOP}p2" >/dev/null 2>&1 || true
sync; losetup -d "$LOOP"

echo "=== v3 built ==="
fdisk -l "$IMG" | tail -4
ls -la "$IMG"
