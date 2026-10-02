#!/bin/bash
# v10 = v9 content in a COMPACT image (2.1 GiB instead of 58 GiB) + one-command
# root-partition expansion, so flashing with Rufus takes minutes instead of ~40.
set -eu
K=/root/r36/linux-6.12.79
ROOT=/root/r36/rootfs
OUT=/root/r36/out
SRC=/mnt/e/ubuntu/build
BLOBS=/mnt/e/ubuntu/artifacts/arkos
IMG="$OUT/r36max2-ubuntu-v10.img"
KVER=6.12.79
JP=/root/r36/joypad/src
AIC=/root/r36/wifi/aic8800dc-linux-patched-main
P2SECTORS=4194304                    # 2 GiB root partition
IMGSECTORS=$((262144 + P2SECTORS))   # ends exactly at the last root sector
WSLNS=$(awk '/^nameserver/{print $2; exit}' /etc/resolv.conf)

echo "=== 1. out-of-tree modules (joypad + AIC8800DC) ==="
make -C "$K" M="$JP" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- DEVICE=RK3326 modules 2>&1 | tail -2
make -C "$AIC/drivers/aic8800" KDIR="$K" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- 2>&1 | tail -2

echo "=== 2. refresh modules inside the rootfs ==="
rm -rf "$OUT/lib/modules"
make -C "$K" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_MOD_PATH="$OUT" modules_install >/dev/null 2>&1
rm -rf "$ROOT/lib/modules/$KVER"
cp -a "$OUT/lib/modules/$KVER" "$ROOT/lib/modules/"
mkdir -p "$ROOT/lib/modules/$KVER/extra"
cp -f /root/r36/joypad/src/rocknix-singleadc-joypad.ko /root/r36/joypad/src/rocknix-joypad.ko "$ROOT/lib/modules/$KVER/extra/"
cp -f /root/r36/wifi/aic8800dc-linux-patched-main/drivers/aic8800/aic_load_fw/aic_load_fw.ko \
      /root/r36/wifi/aic8800dc-linux-patched-main/drivers/aic8800/aic8800_fdrv/aic8800_fdrv.ko \
      "$ROOT/lib/modules/$KVER/extra/"
cp -f "$K"/modules.order "$K"/modules.builtin "$K"/modules.builtin.modinfo "$ROOT/lib/modules/$KVER/"

echo "=== 3. install the expansion helper (needs fdisk/sfdisk) ==="
mount -t proc proc "$ROOT/proc" 2>/dev/null || true
mount -t sysfs sysfs "$ROOT/sys" 2>/dev/null || true
printf 'nameserver %s\n' "$WSLNS" > "$ROOT/etc/resolv.conf"
chroot "$ROOT" /usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -y install fdisk 2>&1 | tail -3
chroot "$ROOT" /usr/bin/env depmod -a "$KVER"
mkdir -p "$ROOT/usr/local/sbin"
cp -f "$SRC/r36-expand-root"   "$ROOT/usr/local/sbin/r36-expand-root"
cp -f "$SRC/r36-finish-expand" "$ROOT/usr/local/sbin/r36-finish-expand"
chmod 755 "$ROOT/usr/local/sbin/r36-expand-root" "$ROOT/usr/local/sbin/r36-finish-expand"
cp -f "$SRC/r36-resize-root.service" "$ROOT/etc/systemd/system/"
mkdir -p "$ROOT/etc/systemd/system/multi-user.target.wants"
ln -sf /etc/systemd/system/r36-resize-root.service "$ROOT/etc/systemd/system/multi-user.target.wants/r36-resize-root.service"
ls -l "$ROOT/sbin/init" "$ROOT/usr/sbin/sfdisk"
umount -f "$ROOT/proc" 2>/dev/null || true
umount -f "$ROOT/sys"  2>/dev/null || true
mount | grep "$ROOT" && { echo "!! rootfs still has mounts, refusing to continue"; exit 1; }
echo "rootfs clean of binds/proc/sys"

echo "=== 4. shrink the rootfs (apt caches are 250 MiB of the 630) ==="
chroot "$ROOT" /usr/bin/env apt-get clean
rm -rf "$ROOT"/var/lib/apt/lists/*
find "$ROOT/var/log" -type f \( -name '*.gz' -o -name '*.[0-9]' \) -delete 2>/dev/null || true
rm -rf "$ROOT/tmp/"* 2>/dev/null || true
du -sk "$ROOT" | awk '{printf "rootfs now: %s KiB = %.2f GiB\n", $1, $1/1048576}'

echo "=== 5. stage the boot files ==="
cp -f "$K/arch/arm64/boot/Image" "$OUT/boot/Image"
cp -f "$K/arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dtb" "$OUT/boot/"
ls -la "$OUT/boot"

echo "=== 6. build the compact image ($((IMGSECTORS/2048)) MiB) ==="
rm -f "$IMG"; truncate -s "$((IMGSECTORS*512))" "$IMG"
printf 'label: dos\nunit: sectors\n\nstart=32768, size=229376, type=c, bootable\nstart=262144, size=%s, type=83\n' "$P2SECTORS" > /tmp/pt10
sfdisk -q "$IMG" < /tmp/pt10
dd if="$BLOBS/idbloader.img" of="$IMG" bs=512 seek=64    conv=notrunc,fsync status=none
dd if="$BLOBS/uboot.img"     of="$IMG" bs=512 seek=16384 conv=notrunc,fsync status=none
dd if="$BLOBS/trust.img"     of="$IMG" bs=512 seek=24576 conv=notrunc,fsync status=none
losetup -P -f "$IMG"; LOOP=$(losetup -j "$IMG" | cut -d: -f1)
for i in 1 2; do for _ in $(seq 1 40); do [ -b "${LOOP}p$i" ] && break; sleep 0.4; done; done
mkfs.vfat -F 32 -n BOOT "${LOOP}p1" >/dev/null
mkfs.ext4 -q -L UBUNTU -m 1 "${LOOP}p2"
MNT=/mnt/r36v10; rm -rf "$MNT"; mkdir -p "$MNT/boot" "$MNT/root"
mount "${LOOP}p1" "$MNT/boot"; mount "${LOOP}p2" "$MNT/root"
cp "$OUT/boot/Image" "$OUT/boot/uInitrd" "$OUT/boot/rk3326-xifan-r36max2.dtb" "$MNT/boot/"
cat > "$MNT/boot/boot.ini" <<'INI'
odroidgoa-uboot-config

setenv bootargs "rootwait rw net.ifnames=0 fbcon=rotate:0 console=tty0 loglevel=7 systemd.show_status=1"

if test -e mmc 1:1 rescue; then
  setenv bootargs "${bootargs} systemd.unit=rescue.target"
  echo "r36max2: RESCUE mode"
fi

setenv loadaddr "0x02000000"
setenv initrd_loadaddr "0x01100000"
setenv dtb_loadaddr "0x01f00000"

load mmc 1:1 ${loadaddr} Image
load mmc 1:1 ${initrd_loadaddr} uInitrd
load mmc 1:1 ${dtb_loadaddr} rk3326-xifan-r36max2.dtb

booti ${loadaddr} ${initrd_loadaddr} ${dtb_loadaddr}
INI
mkdir -p "$MNT/boot/extlinux"
cat > "$MNT/boot/extlinux/extlinux.conf" <<'ELX'
LABEL Ubuntu
  LINUX /Image
  INITRD /uInitrd
  FDT /rk3326-xifan-r36max2.dtb
  APPEND rootwait rw net.ifnames=0 fbcon=rotate:0 console=tty0 loglevel=7 systemd.show_status=1
ELX
rsync -aHAX "$ROOT/" "$MNT/root/"
mkdir -p "$MNT/root/proc" "$MNT/root/sys" "$MNT/root/dev" "$MNT/root/run" "$MNT/root/boot"
rm -f "$MNT/root/etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service"
echo "kernel=$KVER image=compact-2.1GiB expand=r36-expand-root built=$(date -Is)" > "$MNT/root/etc/r36max2-build-info"
df -h "${LOOP}p2" | tail -1 | awk '{print "root partition: size="$2" used="$3" avail="$4}'
sync; umount "$MNT/root"; umount "$MNT/boot"
e2fsck -fy "${LOOP}p2" >/dev/null 2>&1 || true
sync; losetup -d "$LOOP"

echo "=== 7. compress ==="
time xz -T0 -6 -c "$IMG" > /mnt/e/ubuntu/out/r36max2-ubuntu-v10.img.xz
cd /mnt/e/ubuntu/out && sha256sum r36max2-ubuntu-v10.img.xz | tee r36max2-ubuntu-v10.img.xz.sha256
ls -la r36max2-ubuntu-v10.img.xz
echo "=== V10 DONE ==="
