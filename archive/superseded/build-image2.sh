#!/bin/bash
# Assemble the bootable TF image (v2): MBR table so Windows shows the BOOT partition,
# device's own Rockchip blobs, boot.ini with the UPPERCASE magic that EmuELEC's u-boot
# expects, plus extlinux fallbacks.
set -eu
OUT=/root/r36/out
IMG="$OUT/r36max2-ubuntu.img"
ROOT=/root/r36/rootfs
BOOT_SRC="$OUT/boot"
BLOBS=/mnt/e/ubuntu/artifacts          # device's own idbloader/uboot/trust
IMG_GB=${1:-58}

echo "=== create sparse image (${IMG_GB}G) ==="
rm -f "$IMG"; truncate -s "${IMG_GB}G" "$IMG"

echo "=== MBR(DOS) table: p1 FAT32LBA @16MiB 512MiB, p2 Linux rest ==="
# start/size in 512-byte sectors
printf 'label: dos\nunit: sectors\n\nstart=32768, size=1048576, type=c\nstart=1081344, type=83\n' > /tmp/pt
sfdisk -q "$IMG" < /tmp/pt
sfdisk -l "$IMG" | tail -5

echo "=== rockchip blobs (offsets from the device's update.sh) ==="
dd if="$BLOBS/idbloader.img" of="$IMG" bs=512 seek=64    conv=notrunc,fsync status=none
dd if="$BLOBS/uboot.img"     of="$IMG" bs=512 seek=16384 conv=notrunc,fsync status=none
dd if="$BLOBS/trust.img"     of="$IMG" bs=512 seek=24576 conv=notrunc,fsync status=none

echo "=== attach loop ==="
losetup -P -f "$IMG"
LOOP=$(losetup -j "$IMG" | cut -d: -f1)
echo "loop=$LOOP"
for i in 1 2; do for _ in $(seq 1 30); do [ -b "${LOOP}p$i" ] && break; sleep 0.4; done; done
[ -b "${LOOP}p1" ] && [ -b "${LOOP}p2" ] || { echo "FATAL: no partitions on loop"; exit 1; }

echo "=== filesystems ==="
mkfs.vfat -F 32 -n BOOT "${LOOP}p1" >/dev/null
mkfs.ext4 -q -L UBUNTU "${LOOP}p2"
UUID=$(blkid -s UUID -o value "${LOOP}p2")
echo "rootfs UUID=$UUID"

MNT=/mnt/r36img
rm -rf "$MNT"; mkdir -p "$MNT/boot" "$MNT/root"
mount "${LOOP}p1" "$MNT/boot"
mount "${LOOP}p2" "$MNT/root"

echo "=== boot files ==="
cp "$BOOT_SRC/Image" "$MNT/boot/Image"
cp "$BOOT_SRC/Image" "$MNT/boot/KERNEL"                     # name used by EmuELEC configs
cp "$BOOT_SRC/rk3326-xifan-r36max2.dtb" "$MNT/boot/"
cp "$BOOT_SRC/rk3326-xifan-r36max2.dtb" "$MNT/boot/rk3326-evb-lp3-v12-linux.dtb"

# primary path: vendor u-boot script. NOTE the UPPERCASE magic that this device's
# own /flash/boot.ini uses -- lowercase is rejected by that u-boot build.
# An *empty* initrd is passed so booti gets the same 3-argument form ArkOS uses on
# this board; with no /init inside, the kernel unpacks it and proceeds to mount root=.
printf '' | cpio -o -H newc 2>/dev/null | gzip -9 > "$MNT/boot/empty.cpio.gz"
cat > "$MNT/boot/boot.ini" <<BOOT
ODROIDGOA-UBOOT-CONFIG

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

# fallback paths: distro-style extlinux, in case the u-boot resolves to these instead
mkdir -p "$MNT/boot/extlinux"
cat > "$MNT/boot/extlinux/extlinux.conf" <<ELX
LABEL Ubuntu
  LINUX /Image
  FDT /rk3326-xifan-r36max2.dtb
  APPEND root=UUID=$UUID rootwait rw net.ifnames=0 fbcon=rotate:0 console=tty0 quiet loglevel=3
ELX
cp "$MNT/boot/extlinux/extlinux.conf" "$MNT/boot/extlinux/rk3326-evb-lp3-v12-linux.dtb.conf"
printf 'LABEL Ubuntu\n  LINUX /KERNEL\n  FDT /rk3326-evb-lp3-v12-linux.dtb\n  APPEND root=UUID=%s rootwait rw net.ifnames=0 fbcon=rotate:0 console=tty0 quiet loglevel=3\n' "$UUID" \
  > "$MNT/boot/extlinux/rk3326-odroidgo2-linux.dtb.conf"

echo "=== rootfs ==="
rsync -aHAX "$ROOT/" "$MNT/root/"
mkdir -p "$MNT/root/proc" "$MNT/root/sys" "$MNT/root/dev" "$MNT/root/run" "$MNT/root/boot"
echo "kernel=6.12.79 root_uuid=$UUID built=$(date -Is)" > "$MNT/root/etc/r36max2-build-info"

echo "=== finish ==="
sync; umount "$MNT/root"; umount "$MNT/boot"
e2fsck -fy "${LOOP}p2" >/dev/null 2>&1 || true
sync; losetup -d "$LOOP"

echo "=== result ==="
ls -la "$IMG"
echo "apparent: $(du -h --apparent-size "$IMG"|cut -f1)  actual: $(du -h "$IMG"|cut -f1)"
echo "UUID of rootfs for reference: $UUID"
echo "=== IMAGE v2 DONE ==="
