#!/bin/bash
# v6 = v5 + verbose boot (no quiet) + cleaner handover + a "rescue" switch the user can
# flip from Windows, plus no networkd-wait-online stall.
set -eu
OUT=/root/r36/out
IMG="$OUT/r36max2-ubuntu-v6.img"
ROOT=/root/r36/rootfs
BOOT_SRC="$OUT/boot"
BLOBS=/mnt/e/ubuntu/artifacts/arkos
IMG_GB=${1:-58}

rm -f "$IMG"; truncate -s "${IMG_GB}G" "$IMG"
printf 'label: dos\nunit: sectors\n\nstart=32768, size=229376, type=c, bootable\nstart=262144, type=83\n' > /tmp/pt6
sfdisk -q "$IMG" < /tmp/pt6

dd if="$BLOBS/idbloader.img" of="$IMG" bs=512 seek=64    conv=notrunc,fsync status=none
dd if="$BLOBS/uboot.img"     of="$IMG" bs=512 seek=16384 conv=notrunc,fsync status=none
dd if="$BLOBS/trust.img"     of="$IMG" bs=512 seek=24576 conv=notrunc,fsync status=none

losetup -P -f "$IMG"
LOOP=$(losetup -j "$IMG" | cut -d: -f1)
for i in 1 2; do for _ in $(seq 1 30); do [ -b "${LOOP}p$i" ] && break; sleep 0.4; done; done
mkfs.vfat -F 32 -n BOOT "${LOOP}p1" >/dev/null
mkfs.ext4 -q -L UBUNTU "${LOOP}p2"
UUID=$(blkid -s UUID -o value "${LOOP}p2")

MNT=/mnt/r36v6
rm -rf "$MNT"; mkdir -p "$MNT/boot" "$MNT/root"
mount "${LOOP}p1" "$MNT/boot"; mount "${LOOP}p2" "$MNT/root"

cp "$BOOT_SRC/Image"                "$MNT/boot/Image"
cp "$BOOT_SRC/uInitrd"              "$MNT/boot/uInitrd"
cp "$BOOT_SRC/rk3326-xifan-r36max2.dtb" "$MNT/boot/"

cat > "$MNT/boot/boot.ini" <<INI
odroidgoa-uboot-config

# Verbose by default so a stall is visible on the panel.
setenv bootargs "rootwait rw net.ifnames=0 fbcon=rotate:0 console=tty0 loglevel=7 systemd.show_status=1"

# Drop an empty file named "rescue" on this BOOT partition (from Windows) to boot into
# rescue.target instead: minimal services + root shell on the panel console.
if test -e mmc 1:1 rescue; then
  setenv bootargs "\${bootargs} systemd.unit=rescue.target single"
  echo "r36max2: RESCUE mode requested"
fi

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
  APPEND rootwait rw net.ifnames=0 fbcon=rotate:0 console=tty0 loglevel=7 systemd.show_status=1
ELX

rsync -aHAX "$ROOT/" "$MNT/root/"
mkdir -p "$MNT/root/proc" "$MNT/root/sys" "$MNT/root/dev" "$MNT/root/run" "$MNT/root/boot"
# never let networkd-wait-online stall the boot for 2 minutes on a handheld
rm -f "$MNT/root/etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service"
echo "kernel=6.12.79+RDGZIP blobs=arkos initrd=ext4-marker root_uuid=$UUID built=$(date -Is)" > "$MNT/root/etc/r36max2-build-info"

sync; umount "$MNT/root"; umount "$MNT/boot"
e2fsck -fy "${LOOP}p2" >/dev/null 2>&1 || true
sync; losetup -d "$LOOP"

echo "=== verify ==="
losetup -P -f "$IMG"; L2=$(losetup -j "$IMG" | cut -d: -f1)
mkdir -p /mnt/v7/boot /mnt/v7/root
mount -o ro "${L2}p1" /mnt/v7/boot; mount -o ro "${L2}p2" /mnt/v7/root
ls /mnt/v7/boot
grep -c "loglevel=7" /mnt/v7/boot/boot.ini /mnt/v7/boot/extlinux/extlinux.conf
gzip -dc <(dd if=/mnt/v7/boot/uInitrd bs=1 skip=64 status=none) 2>/dev/null | cpio -t --quiet 2>/dev/null | grep -E "^init$"
umount /mnt/v7/root /mnt/v7/boot; losetup -d "$L2"

echo "=== compress ==="
time xz -T0 -6 -c "$IMG" > /mnt/e/ubuntu/out/r36max2-ubuntu-v6.img.xz
ls -la /mnt/e/ubuntu/out/r36max2-ubuntu-v6.img.xz
cd /mnt/e/ubuntu/out && sha256sum r36max2-ubuntu-v6.img.xz | tee r36max2-ubuntu-v6.img.xz.sha256
echo "=== V6 DONE ==="
