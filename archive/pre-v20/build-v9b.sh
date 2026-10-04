#!/bin/bash
# v9b: correct out-of-tree module rebuild paths, refresh rootfs modules, build+pack image.
set -eu
K=/root/r36/linux-6.12.79
ROOT=/root/r36/rootfs
OUT=/root/r36/out
AIC=/root/r36/wifi/aic8800dc-linux-patched-main
JP=/root/r36/joypad/src
BLOBS=/mnt/e/ubuntu/artifacts/arkos
IMG="$OUT/r36max2-ubuntu-v9.img"
KVER=6.12.79
WSLNS=$(awk '/^nameserver/{print $2; exit}' /etc/resolv.conf)

echo "=== 1. joypad module ==="
make -C "$K" M="$JP" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- DEVICE=RK3326 modules 2>&1 | tail -3
echo "=== 2. AIC8800DC module (correct path) ==="
make -C "$AIC/drivers/aic8800" KDIR="$K" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- 2>&1 | tail -4
find "$JP" "$AIC" -name "*.ko" -printf "  built: %f\n"

echo "=== 3. refresh modules into the rootfs ==="
rm -rf "$OUT/lib/modules"
make -C "$K" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_MOD_PATH="$OUT" modules_install >/dev/null 2>&1
rm -rf "$ROOT/lib/modules/$KVER"
cp -a "$OUT/lib/modules/$KVER" "$ROOT/lib/modules/"
mkdir -p "$ROOT/lib/modules/$KVER/extra"
cp -v "$JP"/rocknix-singleadc-joypad.ko "$JP"/rocknix-joypad.ko "$ROOT/lib/modules/$KVER/extra/"
cp -v "$AIC"/drivers/aic8800/aic_load_fw/aic_load_fw.ko \
      "$AIC"/drivers/aic8800/aic8800_fdrv/aic8800_fdrv.ko "$ROOT/lib/modules/$KVER/extra/"
cp -f "$K"/modules.order "$K"/modules.builtin "$K"/modules.builtin.modinfo "$ROOT/lib/modules/$KVER/"
mount -t proc proc "$ROOT/proc" 2>/dev/null || true
printf 'nameserver %s\n' "$WSLNS" > "$ROOT/etc/resolv.conf"
chroot "$ROOT" /usr/bin/env depmod -a "$KVER" && echo "depmod ok"
chroot "$ROOT" /bin/sh -c "modinfo -F vermagic /lib/modules/$KVER/extra/aic8800_fdrv.ko; modinfo -F vermagic /lib/modules/$KVER/extra/rocknix-singleadc-joypad.ko"
ls -la "$ROOT/sbin/init"
umount "$ROOT/proc" 2>/dev/null || true

echo "=== 4. stage boot files ==="
cp -f "$K/arch/arm64/boot/Image" "$OUT/boot/Image"
cp -f "$K/arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dtb" "$OUT/boot/"
ls -la "$OUT/boot"

echo "=== 5. image ==="
rm -f "$IMG"; truncate -s 58G "$IMG"
printf 'label: dos\nunit: sectors\n\nstart=32768, size=229376, type=c, bootable\nstart=262144, type=83\n' > /tmp/pt9b
sfdisk -q "$IMG" < /tmp/pt9b
dd if="$BLOBS/idbloader.img" of="$IMG" bs=512 seek=64    conv=notrunc,fsync status=none
dd if="$BLOBS/uboot.img"     of="$IMG" bs=512 seek=16384 conv=notrunc,fsync status=none
dd if="$BLOBS/trust.img"     of="$IMG" bs=512 seek=24576 conv=notrunc,fsync status=none
losetup -P -f "$IMG"; LOOP=$(losetup -j "$IMG" | cut -d: -f1)
for i in 1 2; do for _ in $(seq 1 30); do [ -b "${LOOP}p$i" ] && break; sleep 0.4; done; done
mkfs.vfat -F 32 -n BOOT "${LOOP}p1" >/dev/null
mkfs.ext4 -q -L UBUNTU "${LOOP}p2"
UUID=$(blkid -s UUID -o value "${LOOP}p2")
MNT=/mnt/r36v9; rm -rf "$MNT"; mkdir -p "$MNT/boot" "$MNT/root"
mount "${LOOP}p1" "$MNT/boot"; mount "${LOOP}p2" "$MNT/root"
cp "$OUT/boot/Image" "$OUT/boot/uInitrd" "$OUT/boot/rk3326-xifan-r36max2.dtb" "$MNT/boot/"
cat > "$MNT/boot/boot.ini" <<INI
odroidgoa-uboot-config

setenv bootargs "rootwait rw net.ifnames=0 fbcon=rotate:0 console=tty0 loglevel=7 systemd.show_status=1"

if test -e mmc 1:1 rescue; then
  setenv bootargs "\${bootargs} systemd.unit=rescue.target"
  echo "r36max2: RESCUE mode"
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
rm -f "$MNT/root/etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service"
echo "kernel=$KVER init=systemd-sysv modules=refreshed avahi=yes built=$(date -Is)" > "$MNT/root/etc/r36max2-build-info"
sync; umount "$MNT/root"; umount "$MNT/boot"
e2fsck -fy "${LOOP}p2" >/dev/null 2>&1 || true
sync; losetup -d "$LOOP"

echo "=== 6. compress ==="
time xz -T0 -6 -c "$IMG" > /mnt/e/ubuntu/out/r36max2-ubuntu-v9.img.xz
cd /mnt/e/ubuntu/out && sha256sum r36max2-ubuntu-v9.img.xz | tee r36max2-ubuntu-v9.img.xz.sha256
ls -la r36max2-ubuntu-v9.img.xz
echo "=== V9 DONE ==="
