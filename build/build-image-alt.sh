#!/bin/bash
# Build an alternative image using ArkOS's proven SD-boot blobs (their u-boot expects the
# lowercase magic). Usage: build-image-alt.sh <gb> <outname>
set -eu
OUT=/root/r36/out
IMG="$OUT/${3:-r36max2-ubuntu-alt.img}"
ROOT=/root/r36/rootfs
BOOT_SRC="$OUT/boot"
BLOBS=/mnt/e/ubuntu/artifacts/arkos    # ArkOS's idbloader/uboot/trust (proven TF boot)
IMG_GB=${1:-58}
MAGIC=${2:-odroidgoa-uboot-config}     # ArkOS u-boot expects lowercase

rm -f "$IMG"; truncate -s "${IMG_GB}G" "$IMG"
printf 'label: dos\nunit: sectors\n\nstart=32768, size=1048576, type=c\nstart=1081344, type=83\n' > /tmp/pt
sfdisk -q "$IMG" < /tmp/pt

dd if="$BLOBS/idbloader.img" of="$IMG" bs=512 seek=64    conv=notrunc,fsync status=none
dd if="$BLOBS/uboot.img"     of="$IMG" bs=512 seek=16384 conv=notrunc,fsync status=none
dd if="$BLOBS/trust.img"     of="$IMG" bs=512 seek=24576 conv=notrunc,fsync status=none

losetup -P -f "$IMG"
LOOP=$(losetup -j "$IMG" | cut -d: -f1)
for i in 1 2; do for _ in $(seq 1 30); do [ -b "${LOOP}p$i" ] && break; sleep 0.4; done; done
mkfs.vfat -F 32 -n BOOT "${LOOP}p1" >/dev/null
mkfs.ext4 -q -L UBUNTU "${LOOP}p2"
UUID=$(blkid -s UUID -o value "${LOOP}p2")
echo "blobs=ArkOS  magic=$MAGIC  rootfs UUID=$UUID"

MNT=/mnt/r36alt
rm -rf "$MNT"; mkdir -p "$MNT/boot" "$MNT/root"
mount "${LOOP}p1" "$MNT/boot"; mount "${LOOP}p2" "$MNT/root"

cp "$BOOT_SRC/Image" "$MNT/boot/Image"; cp "$BOOT_SRC/Image" "$MNT/boot/KERNEL"
cp "$BOOT_SRC/rk3326-xifan-r36max2.dtb" "$MNT/boot/"
cp "$BOOT_SRC/rk3326-xifan-r36max2.dtb" "$MNT/boot/rk3326-evb-lp3-v12-linux.dtb"
printf '' | cpio -o -H newc 2>/dev/null | gzip -9 > "$MNT/boot/empty.cpio.gz"

cat > "$MNT/boot/boot.ini" <<BOOT
$MAGIC

setenv bootargs "root=UUID=$UUID rootwait rw net.ifnames=0 fbcon=rotate:0 console=tty0 quiet loglevel=3"
setenv loadaddr "0x02000000"
setenv initrd_loadaddr "0x01100000"
setenv dtb_loadaddr "0x01f00000"

if load mmc 0:1 \${loadaddr} Image; then
  setenv bootdev 0
elif load mmc 1:1 \${loadaddr} Image; then
  setenv bootdev 1
elif load mmc 2:1 \${loadaddr} Image; then
  setenv bootdev 2
fi

load mmc \${bootdev}:1 \${initrd_loadaddr} empty.cpio.gz
load mmc \${bootdev}:1 \${dtb_loadaddr} rk3326-xifan-r36max2.dtb
booti \${loadaddr} \${initrd_loadaddr} \${dtb_loadaddr}
BOOT

mkdir -p "$MNT/boot/extlinux"
cat > "$MNT/boot/extlinux/extlinux.conf" <<ELX
LABEL Ubuntu
  LINUX /Image
  FDT /rk3326-xifan-r36max2.dtb
  APPEND root=UUID=$UUID rootwait rw net.ifnames=0 fbcon=rotate:0 console=tty0 quiet loglevel=3
ELX
cp "$MNT/boot/extlinux/extlinux.conf" "$MNT/boot/extlinux/rk3326-evb-lp3-v12-linux.dtb.conf"

rsync -aHAX "$ROOT/" "$MNT/root/"
mkdir -p "$MNT/root/proc" "$MNT/root/sys" "$MNT/root/dev" "$MNT/root/run" "$MNT/root/boot"
echo "kernel=6.12.79 blobs=arkos root_uuid=$UUID built=$(date -Is)" > "$MNT/root/etc/r36max2-build-info"

sync; umount "$MNT/root"; umount "$MNT/boot"
e2fsck -fy "${LOOP}p2" >/dev/null 2>&1 || true
sync; losetup -d "$LOOP"
echo "built $IMG  actual=$(du -h "$IMG"|cut -f1)"
