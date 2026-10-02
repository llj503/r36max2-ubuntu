#!/bin/bash
# v10 packaging: the rootfs is already prepared (modules refreshed, caches cleaned,
# fdisk + expand helper installed). Build the compact 2.1 GiB image and xz it.
set -eu
K=/root/r36/linux-6.12.79
ROOT=/root/r36/rootfs
OUT=/root/r36/out
BLOBS=/mnt/e/ubuntu/artifacts/arkos
V="${V:-v10}"
IMG="$OUT/r36max2-ubuntu-${V}.img"
KVER=6.12.79
P2SECTORS=4194304
IMGSECTORS=$((262144 + P2SECTORS))

echo "=== tidy the mount points so rsync sees empty dirs ==="
for m in proc sys dev/pts dev/shm; do umount -l "$ROOT/$m" 2>/dev/null || true; done
find "$ROOT/proc" -mindepth 1 -delete 2>/dev/null || true
find "$ROOT/sys"  -mindepth 1 -delete 2>/dev/null || true
find "$ROOT/dev"  -mindepth 1 -not -path "$ROOT/dev/null" -delete 2>/dev/null || true
rm -rf "$ROOT/run/"* "$ROOT/tmp/"* 2>/dev/null || true
echo "rootfs real size:"; du -sk "$ROOT" | awk '{printf "  %.2f GiB\n", $1/1048576}'
ls -la "$ROOT/proc" "$ROOT/sys" | head -8

echo "=== free disk space in WSL (old 58G raw images) ==="
df -h / | tail -1
for v in v3 v4 v5 v6 v7 v8 v9 alt; do rm -f "$OUT/r36max2-ubuntu-$v.img"; done
echo "removed old raw images; now:"; df -h / | tail -1

echo "=== stage boot files ==="
cp -f "$K/arch/arm64/boot/Image" "$OUT/boot/Image"
cp -f "$K/arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dtb" "$OUT/boot/"
ls -la "$OUT/boot"

echo "=== build the compact image ($((IMGSECTORS/2048)) MiB) ==="
umount /mnt/r36v10/root 2>/dev/null || true
umount /mnt/r36v10/boot 2>/dev/null || true
losetup -a | grep -q "$(readlink -f "$IMG" 2>/dev/null || echo /none)" && losetup -d "$IMG" 2>/dev/null || true
losetup -D 2>/dev/null || true
rm -f "$IMG"; truncate -s "$((IMGSECTORS*512))" "$IMG"
printf 'label: dos\nunit: sectors\n\nstart=32768, size=229376, type=c, bootable\nstart=262144, size=%s, type=83\n' "$P2SECTORS" > /tmp/pt10
sfdisk -q "$IMG" < /tmp/pt10
dd if="$BLOBS/idbloader.img" of="$IMG" bs=512 seek=64    conv=notrunc,fsync status=none
dd if="$BLOBS/uboot.img"     of="$IMG" bs=512 seek=16384 conv=notrunc,fsync status=none
dd if="$BLOBS/trust.img"     of="$IMG" bs=512 seek=24576 conv=notrunc,fsync status=none
losetup -P -f "$IMG"; LOOP=$(losetup -j "$IMG" | cut -d: -f1)
echo "loop=$LOOP"
for i in 1 2; do for _ in $(seq 1 40); do [ -b "${LOOP}p$i" ] && break; sleep 0.4; done; done
ls -l "${LOOP}p1" "${LOOP}p2"
mkfs.vfat -F 32 -n BOOT "${LOOP}p1" >/dev/null
mkfs.ext4 -q -L UBUNTU -m 1 "${LOOP}p2"
MNT=/mnt/r36v10; rm -rf "$MNT"; mkdir -p "$MNT/boot" "$MNT/root"
mount "${LOOP}p1" "$MNT/boot"; mount "${LOOP}p2" "$MNT/root"
cp "$OUT/boot/Image" "$OUT/boot/uInitrd" "$OUT/boot/rk3326-xifan-r36max2.dtb" "$MNT/boot/"
# alternate device trees: switched by RENAMING boot.ini on this FAT partition,
# never by a u-boot variable - the vendor 2017.09 boot.ini parser cannot use
# ${var} as a filename and writes "dtb load fail" to error.log when it tries.
cp "$OUT/boot/rk3326-xifan-r36max2-usbhost.dtb" "$MNT/boot/" 2>/dev/null || true
cat > "$MNT/boot/boot.ini" <<'INI'
odroidgoa-uboot-config

setenv bootargs "rootwait rw net.ifnames=0 fbcon=rotate:0 console=tty0 loglevel=5 systemd.show_status=1"

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
sed 's/rk3326-xifan-r36max2.dtb/rk3326-xifan-r36max2-usbhost.dtb/' "$MNT/boot/boot.ini" > "$MNT/boot/boot-usbhost.ini"
test -n "$(grep -F 'rk3326-xifan-r36max2-usbhost.dtb' "$MNT/boot/boot-usbhost.ini")" || { echo "!! boot-usbhost.ini not built"; exit 1; }
grep -q '{dtb}' "$MNT/boot/boot.ini" && { echo "!! boot.ini still uses a variable dtb name"; exit 1; }
echo "  boot.ini: literal dtb name ok (and boot-usbhost.ini written)"
# --- switches and the alternative AIC firmware set, all readable from Windows ---
mkdir -p "$MNT/boot/fw/aic8800DC"
cp -f /root/r36/aic8800-radxa/src/USB/driver_fw/fw/aic8800DC/*.bin \
      /root/r36/aic8800-radxa/src/USB/driver_fw/fw/aic8800DC/*.txt \
      "$MNT/boot/fw/aic8800DC/" 2>/dev/null || echo "  (no alternate firmware bundle)"
cat > "$MNT/boot/r36-switches.txt" <<'TXT'
r36max2 Ubuntu - 这张 BOOT 分区上的开关

  wifi.txt      换网络 / 换人用这块板子：新建文本文件 wifi.txt，两行
                    SSID=你的WiFi名
                    PSK=你的密码
                （可选第三行 COUNTRY=CN）。开机 30 秒内、以及之后每分钟检查一次，
                内容变了就自动写进 wpa_supplicant 并重连，不用重刷。
                结果写回 wifi-status.txt：连上会给出 IP，连不上会列出附近热点。
                这台机器没有键盘也没有串口，所以这个文件就是唯一的输入通道。
                参考 wifi-example.txt（改名去掉 -example 即可生效）。
  rescue        新建同名空文件 -> 以 rescue.target 启动（还需要能打字才有用）
  noscreen      新建同名空文件 -> 关掉屏幕上的状态页（刷屏或黑屏时用这个自救）
  r36-log       新建同名空文件 -> 立刻再写一份状态报告到 r36-boot.txt
  usbhost       想用第二组 USB 主机控制器（试 Type-C 插键盘）：把 boot-usbhost.ini
                改名成 boot.ini 覆盖掉即可，先备份原来那份；反过来改名恢复
  fw\aic8800DC  一套备用的 AIC WiFi 固件（Radxa bundle 版）。要改用它们：新建空文件
                use-boot-fw，开机会把内核固件搜索路径指到这里并重载 WiFi 驱动

  每次开机 40 秒后（之后每 2 分钟）设备把完整状态写到 r36-boot.txt。
  u-boot 启动失败时自己会往这个分区写 error.log —— 黑屏就先看它。
TXT
cat > "$MNT/boot/wifi-example.txt" <<'EXM'
SSID=my-wifi-name
PSK=my-passphrase-at-least-8-chars
COUNTRY=CN
EXM
mkdir -p "$MNT/boot/extlinux"
cat > "$MNT/boot/extlinux/extlinux.conf" <<'ELX'
LABEL Ubuntu
  LINUX /Image
  INITRD /uInitrd
  FDT /rk3326-xifan-r36max2.dtb
  APPEND rootwait rw net.ifnames=0 fbcon=rotate:0 console=tty0 loglevel=5 systemd.show_status=1
ELX
echo "copying the rootfs..."
rsync -aHAX --exclude='/proc/*' --exclude='/sys/*' --exclude='/dev/*' "$ROOT/" "$MNT/root/"
mkdir -p "$MNT/root/proc" "$MNT/root/sys" "$MNT/root/dev/pts" "$MNT/root/dev/shm" "$MNT/root/run" "$MNT/root/boot"
mknod -m 666 "$MNT/root/dev/null" c 1 3 2>/dev/null || true
mknod -m 666 "$MNT/root/dev/zero" c 1 5 2>/dev/null || true
mknod -m 666 "$MNT/root/dev/random" c 1 8 2>/dev/null || true
mknod -m 666 "$MNT/root/dev/urandom" c 1 9 2>/dev/null || true
mknod -m 600 "$MNT/root/dev/console" c 5 1 2>/dev/null || true
rm -f "$MNT/root/etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service"
echo "kernel=$KVER image=compact-2.1GiB expand=r36-expand-root built=$(date -Is)" > "$MNT/root/etc/r36max2-build-info"
sync
df -h "${LOOP}p2" | tail -1 | awk '{print "root partition: size="$2" used="$3" avail="$4" use%="$5}'
echo "sanity: init=$(ls -l "$MNT/root/sbin/init" 2>/dev/null | awk '{print $NF}')  sfdisk=$(ls "$MNT/root/usr/sbin/sfdisk" 2>/dev/null)  expand=$(ls "$MNT/root/usr/local/sbin/" 2>/dev/null | tr '\n' ' ')"
du -sh "$MNT/root/usr/lib/modules/$KVER" 2>/dev/null
umount "$MNT/root"; umount "$MNT/boot"
e2fsck -fy "${LOOP}p2" >/dev/null 2>&1 || true
sync; losetup -d "$LOOP"

echo "=== compress ==="
time xz -T0 -6 -c "$IMG" > /mnt/e/ubuntu/out/r36max2-ubuntu-${V}.img.xz
cd /mnt/e/ubuntu/out && sha256sum r36max2-ubuntu-${V}.img.xz | tee r36max2-ubuntu-${V}.img.xz.sha256
ls -la r36max2-ubuntu-${V}.img.xz
echo "=== V10 PACK DONE ==="
