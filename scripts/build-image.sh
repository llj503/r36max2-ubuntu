#!/bin/bash
# Assemble a bootable TF-card image for the XiFan R36 Max 2:
#   Rockchip blobs at vendor offsets + GPT(FAT boot, ext4 rootfs) + mainline 6.12.79 + Ubuntu 26.04
set -eu
OUT=/root/r36/out
IMG="$OUT/r36max2-ubuntu.img"
ROOT=/root/r36/rootfs
BOOT_SRC="$OUT/boot"
BLOBS=/mnt/e/ubuntu/artifacts
P2UUID="b3d1a7c2-1111-4f0a-9c66-a1b2c3d4e5f6"   # fixed -> deterministic root=PARTUUID
IMG_GB=${1:-12}

echo "=== create sparse image (${IMG_GB}GB) ==="
rm -f "$IMG"
truncate -s "${IMG_GB}G" "$IMG"

echo "=== GPT: p1 FAT @16MiB (512MiB), p2 rootfs to end ==="
sgdisk -o "$IMG" >/dev/null
sgdisk -n 1:32768:1081343 -c 1:BOOT     -t 1:0c07803b-a4a2-4d12-9647-4a03b0f1bc1c "$IMG" >/dev/null
sgdisk -n 2:1081344:0     -c 2:UBUNTU   -t 2:0fc63daf-8483-47c1-8e7f-1358af9b0000 "$IMG" >/dev/null
sgdisk -u 2:"$P2UUID" "$IMG" >/dev/null
sgdisk -v "$IMG" >/dev/null

echo "=== rockchip boot blobs (offsets copied from the device's own update.sh) ==="
dd if="$BLOBS/idbloader.img" of="$IMG" bs=32k seek=1    conv=notrunc status=none
dd if="$BLOBS/uboot.img"     of="$IMG" bs=64k seek=128  conv=notrunc status=none
dd if="$BLOBS/trust.img"     of="$IMG" bs=64k seek=192  conv=notrunc status=none

echo "=== attach loop device ==="
losetup -PPf /dev/loop0 "$IMG" || losetup -P -f "$IMG"
LOOP=$(losetup -j "$IMG" | cut -d: -f1)
echo "loop=$LOOP"
[ -b "${LOOP}p1" ] && [ -b "${LOOP}p2" ] || { echo "FATAL: loop partitions missing"; exit 1; }

echo "=== filesystems ==="
mkfs.vfat -F 32 -n BOOT "${LOOP}p1" >/dev/null
mkfs.ext4 -q -L UBUNTU "${LOOP}p2"

MNT=/mnt/r36img
rm -rf "$MNT"; mkdir -p "$MNT/boot" "$MNT/root"
mount "${LOOP}p1" "$MNT/boot"
mount "${LOOP}p2" "$MNT/root"

echo "=== boot partition: Image + dtb + boot.ini ==="
cp "$BOOT_SRC/Image" "$MNT/boot/"
cp "$BOOT_SRC/rk3326-xifan-r36max2.dtb" "$MNT/boot/"
cat > "$MNT/boot/boot.ini" <<BOOT
odroidgoa-uboot-config

# Boot Arguments
setenv bootargs "root=PARTUUID=$P2UUID rootwait rw net.ifnames=0 fbcon=rotate:0 console=tty0 quiet loglevel=3"

# Load addresses
setenv loadaddr "0x02000000"
setenv dtb_loadaddr "0x01f00000"

# Try the usual Rockchip mmc numbering, then the other controller, so the card
# boots regardless of which slot/numbering the vendor u-boot enumerates it as.
if load mmc 1:1 \${loadaddr} Image; then
  setenv bootdev 1
elif load mmc 0:1 \${loadaddr} Image; then
  setenv bootdev 0
elif load mmc 2:1 \${loadaddr} Image; then
  setenv bootdev 2
fi

if test \${bootdev} = 1; then
  load mmc 1:1 \${dtb_loadaddr} rk3326-xifan-r36max2.dtb
  booti \${loadaddr} - \${dtb_loadaddr}
elif test \${bootdev} = 0; then
  load mmc 0:1 \${dtb_loadaddr} rk3326-xifan-r36max2.dtb
  booti \${loadaddr} - \${dtb_loadaddr}
elif test \${bootdev} = 2; then
  load mmc 2:1 \${dtb_loadaddr} rk3326-xifan-r36max2.dtb
  booti \${loadaddr} - \${dtb_loadaddr}
fi
BOOT

echo "=== rootfs -> p2 ==="
rsync -aHAX "$ROOT/" "$MNT/root/"
mkdir -p "$MNT/root/proc" "$MNT/root/sys" "$MNT/root/dev" "$MNT/root/run" "$MNT/root/boot"
echo "kernel=6.12.79 recipe=rocknix-RK3326 built=$(date -Is) root_partuuid=$P2UUID" \
  > "$MNT/root/etc/r36max2-build-info"

echo "=== finish ==="
sync
umount "$MNT/root"
umount "$MNT/boot"
e2fsck -fy "${LOOP}p2" >/dev/null 2>&1 || true
sync
losetup -d "$LOOP"

echo "=== result ==="
ls -la "$IMG"
echo "apparent: $(du -h --apparent-size "$IMG" | cut -f1)   actual: $(du -h "$IMG" | cut -f1)"
echo "=== IMAGE BUILD DONE ==="
