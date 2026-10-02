#!/bin/bash
# v4 = copy of the *proven* ArkOS boot recipe, with our mainline kernel + Ubuntu rootfs.
# Reference: the user's working arkos4clone card (J: BOOT partition) uses
#   - its own blobs (idbloader 176452 / uboot / trust) at 32KiB / 8MiB / 12MiB
#   - p1 FAT32 LBA starting at 16MiB (112MiB), p2 rootfs at 128MiB
#   - boot.ini whose first line is the LOWERCASE magic (ArkOS u-boot checks "%s-uboot-config")
#   - load mmc 1:1 Image / uInitrd / <dtb>  then  booti <k> <i> <dtb>
#   - uInitrd is a mkimage legacy-wrapped ramdisk (u-boot strips the header for booti)
set -eu
OUT=/root/r36/out
IMG="$OUT/r36max2-ubuntu-v4.img"
ROOT=/root/r36/rootfs
BOOT_SRC="$OUT/boot"
BLOBS=/mnt/e/ubuntu/artifacts/arkos
IMG_GB=${1:-58}

rm -f "$IMG"; truncate -s "${IMG_GB}G" "$IMG"
printf 'label: dos\nunit: sectors\n\nstart=32768, size=229376, type=c, bootable\nstart=262144, type=83\n' > /tmp/pt4
sfdisk -q "$IMG" < /tmp/pt4

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

MNT=/mnt/r36v4
rm -rf "$MNT"; mkdir -p "$MNT/boot" "$MNT/root"
mount "${LOOP}p1" "$MNT/boot"; mount "${LOOP}p2" "$MNT/root"

cp "$BOOT_SRC/Image" "$MNT/boot/Image"
cp "$BOOT_SRC/rk3326-xifan-r36max2.dtb" "$MNT/boot/rk3326-xifan-r36max2.dtb"

# legacy-wrapped empty initramfs, same format as the working card's uInitrd
printf '' | cpio -o -H newc 2>/dev/null | gzip -9 > /tmp/initrd_empty.cpio.gz
mkimage -A arm64 -O linux -T ramdisk -C gzip -n "uInitrd" -d /tmp/initrd_empty.cpio.gz "$MNT/boot/uInitrd" >/dev/null

# the authoritative entry point for ArkOS's u-boot
cat > "$MNT/boot/boot.ini" <<INI
odroidgoa-uboot-config

# Boot Arguments
setenv bootargs "root=UUID=$UUID rootwait rw fsck.repair=yes net.ifnames=0 fbcon=rotate:0 console=tty0 quiet splash consoleblank=0"

# Booting
setenv loadaddr "0x02000000"
setenv initrd_loadaddr "0x01100000"
setenv dtb_loadaddr "0x01f00000"

load mmc 1:1 \${loadaddr} Image
load mmc 1:1 \${initrd_loadaddr} uInitrd

load mmc 1:1 \${dtb_loadaddr} rk3326-xifan-r36max2.dtb

booti \${loadaddr} \${initrd_loadaddr} \${dtb_loadaddr}
INI

# extra fallbacks (harmless if unused): distro extlinux + boot.scr
mkdir -p "$MNT/boot/extlinux"
cat > "$MNT/boot/extlinux/extlinux.conf" <<ELX
LABEL Ubuntu
  LINUX /Image
  INITRD /uInitrd
  FDT /rk3326-xifan-r36max2.dtb
  APPEND root=UUID=$UUID rootwait rw net.ifnames=0 fbcon=rotate:0 console=tty0 quiet
ELX
{ echo 'setenv bootargs "root=UUID='"$UUID"' rootwait rw net.ifnames=0 fbcon=rotate:0 console=tty0 quiet"';
  echo 'fatload mmc 1:1 0x02000000 Image';
  echo 'fatload mmc 1:1 0x01100000 uInitrd';
  echo 'fatload mmc 1:1 0x01f00000 rk3326-xifan-r36max2.dtb';
  echo 'booti 0x02000000 0x01100000 0x01f00000'; } > /tmp/boot4.cmd
mkimage -T script -C none -A arm64 -n "Ubuntu R36Max2" -d /tmp/boot4.cmd "$MNT/boot/boot.scr" >/dev/null

rsync -aHAX "$ROOT/" "$MNT/root/"
mkdir -p "$MNT/root/proc" "$MNT/root/sys" "$MNT/root/dev" "$MNT/root/run" "$MNT/root/boot"
echo "kernel=6.12.79 blobs=arkos entry=boot.ini(lowercase) root_uuid=$UUID built=$(date -Is)" > "$MNT/root/etc/r36max2-build-info"

sync; umount "$MNT/root"; umount "$MNT/boot"
e2fsck -fy "${LOOP}p2" >/dev/null 2>&1 || true
sync; losetup -d "$LOOP"

echo "=== v4 layout ==="
fdisk -l "$IMG" | tail -4
echo "=== v4 built: $(du -h "$IMG" | cut -f1) actual ==="
