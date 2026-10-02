#!/bin/bash
# v5 = v4's proven ArkOS boot contract + kernel rebuilt with RD_GZIP + real initramfs.
# root= is no longer needed in the cmdline (the initramfs locates the rootfs by marker),
# which removes the "root= is invalid" failure entirely and also survives mmcblk renumbering.
set -eu
OUT=/root/r36/out
IMG="$OUT/r36max2-ubuntu-v5.img"
ROOT=/root/r36/rootfs
BOOT_SRC="$OUT/boot"
BLOBS=/mnt/e/ubuntu/artifacts/arkos
IMG_GB=${1:-58}

rm -f "$IMG"; truncate -s "${IMG_GB}G" "$IMG"
printf 'label: dos\nunit: sectors\n\nstart=32768, size=229376, type=c, bootable\nstart=262144, type=83\n' > /tmp/pt5
sfdisk -q "$IMG" < /tmp/pt5

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

MNT=/mnt/r36v5
rm -rf "$MNT"; mkdir -p "$MNT/boot" "$MNT/root"
mount "${LOOP}p1" "$MNT/boot"; mount "${LOOP}p2" "$MNT/root"

cp "$BOOT_SRC/Image"                "$MNT/boot/Image"
cp "$BOOT_SRC/uInitrd"              "$MNT/boot/uInitrd"
cp "$BOOT_SRC/rk3326-xifan-r36max2.dtb" "$MNT/boot/"

cat > "$MNT/boot/boot.ini" <<INI
odroidgoa-uboot-config

# Boot Arguments (root device is located by the initramfs, so no root= needed)
setenv bootargs "rootwait rw net.ifnames=0 fbcon=rotate:0 console=tty0 quiet splash consoleblank=0"

# Booting
setenv loadaddr "0x02000000"
setenv initrd_loadaddr "0x01100000"
setenv dtb_loadaddr "0x01f00000"

load mmc 1:1 \${loadaddr} Image
load mmc 1:1 \${initrd_loadaddr} uInitrd

load mmc 1:1 \${dtb_loadaddr} rk3326-xifan-r36max2.dtb

booti \${loadaddr} \${initrd_loadaddr} \${dtb_loadaddr}
INI

mkdir -p "$MNT/boot/extlinux"
cat > "$MNT/boot/extlinux/extlinux.conf" <<ELX
LABEL Ubuntu
  LINUX /Image
  INITRD /uInitrd
  FDT /rk3326-xifan-r36max2.dtb
  APPEND rootwait rw net.ifnames=0 fbcon=rotate:0 console=tty0 quiet
ELX
{ echo 'setenv bootargs "rootwait rw net.ifnames=0 fbcon=rotate:0 console=tty0 quiet"';
  echo 'fatload mmc 1:1 0x02000000 Image';
  echo 'fatload mmc 1:1 0x01100000 uInitrd';
  echo 'fatload mmc 1:1 0x01f00000 rk3326-xifan-r36max2.dtb';
  echo 'booti 0x02000000 0x01100000 0x01f00000'; } > /tmp/boot5.cmd
mkimage -T script -C none -A arm64 -n "Ubuntu R36Max2" -d /tmp/boot5.cmd "$MNT/boot/boot.scr" >/dev/null

rsync -aHAX "$ROOT/" "$MNT/root/"
mkdir -p "$MNT/root/proc" "$MNT/root/sys" "$MNT/root/dev" "$MNT/root/run" "$MNT/root/boot"
echo "kernel=6.12.79+RDGZIP blobs=arkos initrd=marker-scan root_uuid=$UUID built=$(date -Is)" > "$MNT/root/etc/r36max2-build-info"

sync; umount "$MNT/root"; umount "$MNT/boot"
e2fsck -fy "${LOOP}p2" >/dev/null 2>&1 || true
sync; losetup -d "$LOOP"

echo "=== verify v5 ==="
losetup -P -f "$IMG"
L2=$(losetup -j "$IMG" | cut -d: -f1)
mkdir -p /mnt/v6/boot /mnt/v6/root
mount -o ro "${L2}p1" /mnt/v6/boot; mount -o ro "${L2}p2" /mnt/v6/root
ls -la /mnt/v6/boot | tail -6
echo "--- init at initrd root? ---"
dd if=/mnt/v6/boot/uInitrd bs=1 skip=64 status=none | gzip -dc 2>/dev/null | cpio -t --quiet 2>/dev/null | grep -E "^init$|^bin/busybox$"
echo "--- marker in rootfs? ---"; cat /mnt/v6/root/etc/r36max2-build-info
umount /mnt/v6/root /mnt/v6/boot; losetup -d "$L2"

echo "=== compress ==="
time xz -T0 -6 -c "$IMG" > /mnt/e/ubuntu/out/r36max2-ubuntu-v5.img.xz
ls -la /mnt/e/ubuntu/out/r36max2-ubuntu-v5.img.xz
cd /mnt/e/ubuntu/out && sha256sum r36max2-ubuntu-v5.img.xz | tee r36max2-ubuntu-v5.img.xz.sha256
echo "=== V5 DONE ==="
