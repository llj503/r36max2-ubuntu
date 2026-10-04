#!/bin/bash
# v9: sound machine driver built-in (correct symbol name), all modules rebuilt + reinstalled
# into the rootfs against the current tree, then image + initrd + pack.
set -eu
K=/root/r36/linux-6.12.79
ROOT=/root/r36/rootfs
OUT=/root/r36/out
BLOBS=/mnt/e/ubuntu/artifacts/arkos
IMG="$OUT/r36max2-ubuntu-v9.img"
WSLNS=$(awk '/^nameserver/{print $2; exit}' /etc/resolv.conf)

cd "$K"
echo "=== before ==="
grep -E "^CONFIG_SND_SIMPLE_CARD|^# CONFIG_SND_SIMPLE_CARD|^CONFIG_DRM_PANFROST" .config || true

echo "=== enable ASoC machine drivers built-in ==="
cat >> .config <<'CFG'
CONFIG_SND_SIMPLE_CARD=y
CONFIG_SND_SIMPLE_CARD_UTILS=y
CFG
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig >/dev/null 2>&1
grep -E "^CONFIG_SND_SIMPLE_CARD|^CONFIG_SND_SIMPLE_CARD_UTILS|^CONFIG_DRM_ROCKCHIP|^CONFIG_MEMCG" .config

echo "=== rebuild Image + dtbs + modules ==="
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)" Image dtbs modules > /root/r36/b9.log 2>&1
tail -2 /root/r36/b9.log
ls -la arch/arm64/boot/Image arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dtb

echo "=== rebuild out-of-tree modules against the fresh tree ==="
make -C "$K" M=/root/r36/joypad/src ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- DEVICE=RK3326 modules > /root/r36/b9mod.log 2>&1
make -C drivers/aic8800 KDIR="$K" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- >> /root/r36/b9mod.log 2>&1
find /root/r36/joypad/src /root/r36/wifi -name "*.ko" -printf "%f\n" | sort

echo "=== refresh modules inside the rootfs ==="
rm -rf "$OUT/lib/modules"
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_MOD_PATH="$OUT" modules_install > /dev/null 2>&1
KVER=$(make kernelversion)
rm -rf "$ROOT/lib/modules/$KVER"
cp -a "$OUT/lib/modules/$KVER" "$ROOT/lib/modules/"
mkdir -p "$ROOT/lib/modules/$KVER/extra"
cp -v /root/r36/joypad/src/rocknix-singleadc-joypad.ko /root/r36/joypad/src/rocknix-joypad.ko "$ROOT/lib/modules/$KVER/extra/"
find /root/r36/wifi -name "aic_load_fw.ko" -o -name "aic8800_fdrv.ko" | xargs cp -t "$ROOT/lib/modules/$KVER/extra/"
cp -f modules.order modules.builtin modules.builtin.modinfo "$ROOT/lib/modules/$KVER/"
mount -t proc proc "$ROOT/proc" 2>/dev/null || true
printf 'nameserver %s\n' "$WSLNS" > "$ROOT/etc/resolv.conf"
chroot "$ROOT" /usr/bin/env depmod -a "$KVER"
echo "--- vermagic consistency ---"
chroot "$ROOT" /bin/sh -c "modinfo -F vermagic /lib/modules/$KVER/extra/aic8800_fdrv.ko; modinfo -F vermagic /lib/modules/$KVER/extra/rocknix-singleadc-joypad.ko; uname -r"
chroot "$ROOT" /bin/sh -c 'ls /lib/modules/'"$KVER"'/kernel/sound/soc/generic/ 2>/dev/null || echo "(simple-card is built-in, no .ko expected)"'
echo "--- init still present ---"; ls -la "$ROOT/sbin/init"

echo "=== stage boot files ==="
cp -f arch/arm64/boot/Image "$OUT/boot/Image"
cp -f arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dtb "$OUT/boot/"

echo "=== build image ==="
rm -f "$IMG"; truncate -s 58G "$IMG"
printf 'label: dos\nunit: sectors\n\nstart=32768, size=229376, type=c, bootable\nstart=262144, type=83\n' > /tmp/pt9
sfdisk -q "$IMG" < /tmp/pt9
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
cp "$OUT/boot/Image" "$OUT/boot/uInitrd" "$MNT/boot/"
cp "$OUT/boot/rk3326-xifan-r36max2.dtb" "$MNT/boot/"
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
echo "kernel=$KVER init=systemd-sysv sound=builtin modules=refreshed built=$(date -Is)" > "$MNT/root/etc/r36max2-build-info"
sync; umount "$MNT/root"; umount "$MNT/boot"
e2fsck -fy "${LOOP}p2" >/dev/null 2>&1 || true
sync; losetup -d "$LOOP"
echo "=== compress ==="
time xz -T0 -6 -c "$IMG" > /mnt/e/ubuntu/out/r36max2-ubuntu-v9.img.xz
cd /mnt/e/ubuntu/out && sha256sum r36max2-ubuntu-v9.img.xz | tee r36max2-ubuntu-v9.img.xz.sha256
echo "=== V9 DONE ==="
