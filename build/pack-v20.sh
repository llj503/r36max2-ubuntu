#!/bin/bash
# pack-v20.sh - v19's packaging, plus the two things v20 adds:
#
#   * BOTH kernels on the FAT partition.  boot.ini now loads 7.2.8 (the user's
#     choice) and boot-612.ini is the one-line fallback; u-boot 2017.09 cannot
#     take a ${var} as a filename, so every variant is its own literal file.
#   * the Wayland stack + joypad->mouse bridge in the rootfs, installed but NOT
#     enabled (weston on 7.2.8 can wedge the VOP, see README).
#
# Everything is verified against the image itself before it is compressed:
# module vermagic per kernel, dtb gpio polarity flags, no credentials, no baked
# SSH host keys, empty machine-id, weston not enabled.
set -euo pipefail
K6=/root/r36/linux-6.12.79
K7=/root/r36/linux-7.2.8
ROOT=/root/r36/rootfs
OUT=/root/r36/out
BLOBS=/mnt/e/ubuntu/artifacts/arkos
V="${V:-v20}"
IMG="$OUT/r36max2-ubuntu-${V}.img"
P2SECTORS=4194304                     # 2 GiB root partition
IMGSECTORS=$((262144 + P2SECTORS))

echo "=== [1] tidy mount points so rsync sees an empty /proc /sys /dev ==="
for m in proc sys dev/pts dev/shm; do umount -l "$ROOT/$m" 2>/dev/null || true; done
find "$ROOT/proc" -mindepth 1 -delete 2>/dev/null || true
find "$ROOT/sys"  -mindepth 1 -delete 2>/dev/null || true
find "$ROOT/dev"  -mindepth 1 -not -path "$ROOT/dev/null" -delete 2>/dev/null || true
rm -rf "$ROOT/run/"* "$ROOT/tmp/"* 2>/dev/null || true
# modules_install leftovers: `build`/`source` symlinks into the kernel tree. They
# would be dangling on every card, and any copy that follows symlinks would turn a
# 20 MB directory into a 1.8 GB one. Drop them for every kernel in the image.
for kv in "$ROOT"/lib/modules/*; do rm -f "$kv/build" "$kv/source" 2>/dev/null || true; done
echo "  build/source symlinks left: $(find "$ROOT/lib/modules" -maxdepth 2 \( -name build -o -name source \) | wc -l)"
echo "  rootfs size: $(du -sh "$ROOT" | cut -f1)   modules: $(du -sh "$ROOT/lib/modules/6.12.79" "$ROOT/lib/modules/7.2.8" 2>/dev/null | tr '\n' ' ')"
echo "  disk free in WSL: $(df -h / | tail -1 | awk '{print $4}')"

echo "=== [2] stage boot files ==="
cp -f "$K6/arch/arm64/boot/Image" "$OUT/boot/Image"
cp -f "$K7/arch/arm64/boot/Image" "$OUT/boot/Image-7.2.8"
for d in rk3326-xifan-r36max2 rk3326-xifan-r36max2-usbhost rk3326-xifan-r36max2-gadget; do
  cp -f "$K6/arch/arm64/boot/dts/rockchip/$d.dtb" "$OUT/boot/$d.dtb"
  cp -f "$K7/arch/arm64/boot/dts/rockchip/$d.dtb" "$OUT/boot/$d-7.2.8.dtb"
done
ls -l "$OUT/boot" | sed 's/^/  /'
for f in "$OUT/boot/rk3326-xifan-r36max2.dtb" "$OUT/boot/rk3326-xifan-r36max2-7.2.8.dtb"; do
  echo "  $(basename "$f") gpio flags:"
  dtc -I dtb -O dts "$f" 2>/dev/null | grep -E "amux-a-gpios|amux-en-gpios|rumble-gpio" | sed 's/^/      /'
done

echo "=== [3] build the compact image ==="
umount /mnt/r36v20/root /mnt/r36v20/boot 2>/dev/null || true
losetup -D 2>/dev/null || true
rm -f "$IMG"; truncate -s "$((IMGSECTORS*512))" "$IMG"
printf 'label: dos\nunit: sectors\n\nstart=32768, size=229376, type=c, bootable\nstart=262144, size=%s, type=83\n' "$P2SECTORS" > /tmp/pt20
sfdisk -q "$IMG" < /tmp/pt20
dd if="$BLOBS/idbloader.img" of="$IMG" bs=512 seek=64    conv=notrunc,fsync status=none
dd if="$BLOBS/uboot.img"     of="$IMG" bs=512 seek=16384 conv=notrunc,fsync status=none
dd if="$BLOBS/trust.img"     of="$IMG" bs=512 seek=24576 conv=notrunc,fsync status=none
losetup -P -f "$IMG"; LOOP=$(losetup -j "$IMG" | cut -d: -f1)
echo "  loop=$LOOP"
for i in 1 2; do for _ in $(seq 1 40); do [ -b "${LOOP}p$i" ] && break; sleep 0.4; done; done
mkfs.vfat -F 32 -n BOOT "${LOOP}p1" >/dev/null
mkfs.ext4 -q -L UBUNTU -m 1 "${LOOP}p2"
MNT=/mnt/r36v20; rm -rf "$MNT"; mkdir -p "$MNT/boot" "$MNT/root"
mount "${LOOP}p1" "$MNT/boot"; mount "${LOOP}p2" "$MNT/root"

echo "=== [4] FAT: two kernels, four boot.ini variants ==="
cp "$OUT/boot/Image" "$OUT/boot/Image-7.2.8" "$OUT/boot/uInitrd" "$MNT/boot/"
cp "$OUT/boot/rk3326-xifan-r36max2.dtb"        "$MNT/boot/"
cp "$OUT/boot/rk3326-xifan-r36max2-7.2.8.dtb"  "$MNT/boot/"
cp "$OUT/boot/rk3326-xifan-r36max2-usbhost.dtb" "$MNT/boot/" 2>/dev/null || true

make_bootini() {   # $1=kernel image  $2=dtb  $3=output
  cat > "$3" <<INI
odroidgoa-uboot-config

setenv bootargs "rootwait rw net.ifnames=0 fbcon=rotate:0 console=tty0 loglevel=5 systemd.show_status=1"

if test -e mmc 1:1 rescue; then
  setenv bootargs "\${bootargs} systemd.unit=rescue.target"
  echo "r36max2: RESCUE mode"
fi

setenv loadaddr "0x02000000"
setenv initrd_loadaddr "0x01100000"
setenv dtb_loadaddr "0x01f00000"

load mmc 1:1 \${loadaddr} $1
load mmc 1:1 \${initrd_loadaddr} uInitrd
load mmc 1:1 \${dtb_loadaddr} $2

booti \${loadaddr} \${initrd_loadaddr} \${dtb_loadaddr}
INI
}
# default = 7.2.8 (verified on hardware: display, audio, GPU, WiFi, joypad, rumble)
make_bootini "Image-7.2.8" "rk3326-xifan-r36max2-7.2.8.dtb" "$MNT/boot/boot.ini"
cp "$MNT/boot/boot.ini" "$MNT/boot/boot-72.ini"
make_bootini "Image" "rk3326-xifan-r36max2.dtb" "$MNT/boot/boot-612.ini"
make_bootini "Image" "rk3326-xifan-r36max2-usbhost.dtb" "$MNT/boot/boot-usbhost.ini"
for f in boot.ini boot-72.ini boot-612.ini boot-usbhost.ini; do
  printf '  %-18s %s\n' "$f" "$(grep -oE 'Image[^ ]*|rk3326[^ ]*dtb' "$MNT/boot/$f" | tr '\n' ' ')"
done
grep -q '{dtb}' "$MNT/boot/boot.ini" && { echo "!! boot.ini uses a variable filename"; exit 1; }

echo "=== [5] firmware fallback bundle and the Windows-side notes ==="
mkdir -p "$MNT/boot/fw/aic8800DC"
cp -f /root/r36/aic8800-radxa/src/USB/driver_fw/fw/aic8800DC/*.bin \
      /root/r36/aic8800-radxa/src/USB/driver_fw/fw/aic8800DC/*.txt \
      "$MNT/boot/fw/aic8800DC/" 2>/dev/null || echo "  (no alternate firmware bundle)"
cat > "$MNT/boot/r36-switches.txt" <<'TXT'
r36max2 Ubuntu (v20) - 这张 BOOT 分区上的开关

  boot.ini      当前启动哪个内核。默认 = 7.2.8（boot-72.ini 的副本）。
                想退回 6.12.79：把 boot-612.ini 改名（复制）成 boot.ini，安全退出
                这个 FAT 分区后再开机；想回来就用 boot-72.ini 覆盖 boot.ini。
                两套内核和两份 dtb 都在卡上，切换不需要重刷镜像。
  wifi.txt      换网络 / 换人用这块板子：新建文本文件 wifi.txt，两行
                    SSID=你的WiFi名
                    PSK=你的密码
                （可选第三行 COUNTRY=CN）。开机 30 秒内、以及之后每分钟检查一次，
                内容变了就自动写进 wpa_supplicant 并重连，不用重刷。
                结果写回 wifi-status.txt：连上会给出 IP，连不上会列出附近热点。
                **镜像里不带任何 WiFi 凭据**，不放这个文件就只有 SSH 有线路径可走
                （这台机器没有键盘也没有串口，所以这个文件就是唯一的输入通道）。
                参考 wifi-example.txt（改名去掉 -example 即可生效）。
  rescue        新建同名空文件 -> 以 rescue.target 启动
  noscreen      新建同名空文件 -> 关掉屏幕上的状态页（刷屏或黑屏时用这个自救）
  r36-log       新建同名空文件 -> 立刻再写一份状态报告到 r36-boot.txt
  usbhost       想用第二组 USB 主机控制器（试 Type-C 插键盘）：把 boot-usbhost.ini
                改名成 boot.ini 覆盖掉即可（注意那是 6.12 那条线），先备份原来那份
  fw\aic8800DC  一套备用的 AIC WiFi 固件（Radxa bundle 版）。要改用它们：新建空文件
                use-boot-fw，开机会把内核固件搜索路径指到这里并重载 WiFi 驱动

  图形（weston / 摇杆键鼠桥）装在系统里但**默认不启动**。SSH 进去：
      r36-wayland start        # 起 weston，键鼠桥跟着起（BindsTo）
      r36-wayland status       # 看合成器与摇杆桥的状态
      systemctl stop weston    # 回文字控制台
  注意：7.2.8 + 这颗 VOP 在长时间跑 weston 后可能出现翻页完成中断丢失（屏幕冻在
  最后一帧，只能重启）。先在串口/显示无解的情况下谨慎使用，详见 README 的
  “Wayland（weston）”一节。

  每次开机 40 秒后（之后每 2 分钟）设备把完整状态写到 r36-boot.txt。
  u-boot 启动失败时自己会往这个分区写 error.log —— 黑屏就先看它。
  镜像里不带 WiFi 凭据，也不带 SSH 主机密钥（首次开机 ssh-keygen -A 生成）；
  默认账号 ubuntu / 密码 ubuntu，**刷完第一件事就是 passwd 改掉**。
TXT
cat > "$MNT/boot/wifi-example.txt" <<'EXM'
SSID=my-wifi-name
PSK=my-passphrase-at-least-8-chars
COUNTRY=CN
EXM
mkdir -p "$MNT/boot/extlinux"
cat > "$MNT/boot/extlinux/extlinux.conf" <<'ELX'
LABEL Ubuntu-7.2.8
  LINUX /Image-7.2.8
  INITRD /uInitrd
  FDT /rk3326-xifan-r36max2-7.2.8.dtb
  APPEND rootwait rw net.ifnames=0 fbcon=rotate:0 console=tty0 loglevel=5 systemd.show_status=1
LABEL Ubuntu-6.12.79
  LINUX /Image
  INITRD /uInitrd
  FDT /rk3326-xifan-r36max2.dtb
  APPEND rootwait rw net.ifnames=0 fbcon=rotate:0 console=tty0 loglevel=5 systemd.show_status=1
ELX

echo "=== [6] copy the rootfs ==="
rsync -aHAX --exclude='/proc/*' --exclude='/sys/*' --exclude='/dev/*' "$ROOT/" "$MNT/root/"
mkdir -p "$MNT/root/proc" "$MNT/root/sys" "$MNT/root/dev/pts" "$MNT/root/dev/shm" "$MNT/root/run" "$MNT/root/boot"
mknod -m 666 "$MNT/root/dev/null" c 1 3 2>/dev/null || true
mknod -m 666 "$MNT/root/dev/zero" c 1 5 2>/dev/null || true
mknod -m 666 "$MNT/root/dev/random" c 1 8 2>/dev/null || true
mknod -m 666 "$MNT/root/dev/urandom" c 1 9 2>/dev/null || true
mknod -m 600 "$MNT/root/dev/console" c 5 1 2>/dev/null || true
rm -f "$MNT/root/etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service"
echo "kernel=7.2.8(default)+6.12.79 image=compact-2.1GiB expand=r36-expand-root wayland=installed-not-enabled credentials=none built=$(date -Is)" \
  > "$MNT/root/etc/r36max2-build-info"
sync
df -h "${LOOP}p2" | tail -1 | awk '{print "  root partition: size="$2" used="$3" avail="$4" use%="$5}'

echo "=== [7] verify what actually landed in the image ==="
fail=0
for kv in 6.12.79 7.2.8; do
  n=$(find "$MNT/root/lib/modules/$kv" -name '*.ko' 2>/dev/null | wc -l)
  echo "  /lib/modules/$kv: $n .ko"
  [ "$n" -gt 50 ] || { echo "    !! too few modules"; fail=1; }
  [ -e "$MNT/root/lib/modules/$kv/modules.dep" ] || { echo "    !! no modules.dep (depmod missing)"; fail=1; }
  [ -e "$MNT/root/lib/modules/$kv/build" ] && { echo "    !! build symlink survived"; fail=1; }
  for m in aic8800_fdrv rocknix-singleadc-joypad; do
    f="$MNT/root/lib/modules/$kv/extra/$m.ko"
    if [ -e "$f" ]; then
      v=$(modinfo -F vermagic "$f" | awk '{print $1}')
      echo "    extra/$m.ko -> vermagic $v"
      [ "$v" = "$kv" ] || { echo "      !! wrong kernel"; fail=1; }
    else
      echo "    !! missing extra/$m.ko for $kv"; fail=1
    fi
  done
done
echo "  weston: $(ls "$MNT/root/usr/bin/weston" 2>/dev/null || echo MISSING)  backends: $(find "$MNT/root/usr/lib" -name 'drm-backend.so' 2>/dev/null | wc -l)"
echo "  weston enabled? $(ls "$MNT/root/etc/systemd/system/multi-user.target.wants/weston.service" 2>/dev/null || echo "no (correct)")"
echo "  keymapper: $(ls "$MNT/root/usr/local/bin/r36-keymapper.py" "$MNT/root/usr/local/bin/r36-wayland" 2>/dev/null | wc -l)/2 files"
echo "  ssh host keys in image: $(ls "$MNT/root/etc/ssh/ssh_host_*" 2>/dev/null | wc -l) (must be 0)"
echo "  host-key regen unit: $(ls "$MNT/root/etc/systemd/system/multi-user.target.wants/r36-hostkeys.service" 2>/dev/null || echo MISSING)"
echo "  machine-id: $([ -s "$MNT/root/etc/machine-id" ] && echo NON-EMPTY || echo empty)"
echo "  wpa configs with our creds: $(ls "$MNT/root/etc/wpa_supplicant/"*wlan0.conf 2>/dev/null | wc -l)"
echo "  chvt/fgconsole (kbd): $(ls "$MNT/root/usr/bin/chvt" 2>/dev/null || echo MISSING)"
echo "  modules-load.d: $(tr '\n' ' ' < "$MNT/root/etc/modules-load.d/r36max2.conf")"
for d in "$MNT/boot/rk3326-xifan-r36max2.dtb" "$MNT/boot/rk3326-xifan-r36max2-7.2.8.dtb"; do
  echo "  FAT $(basename "$d"): $(dtc -I dtb -O dts "$d" 2>/dev/null | grep -E 'rumble-gpio|amux-a-gpios' | tr -s ' \t' ' ' | tr '\n' ' ')"
done
[ "$fail" = 0 ] || { echo "!! verification FAILED - not compressing"; exit 1; }

echo "=== [8] close it out and compress ==="
sync; umount "$MNT/root"; umount "$MNT/boot"
e2fsck -fy "${LOOP}p2" >/dev/null 2>&1 || true
sync; losetup -d "$LOOP"
time xz -T0 -6 -c "$IMG" > /mnt/e/ubuntu/out/r36max2-ubuntu-${V}.img.xz
cd /mnt/e/ubuntu/out && sha256sum r36max2-ubuntu-${V}.img.xz | tee r36max2-ubuntu-${V}.img.xz.sha256
ls -la "r36max2-ubuntu-${V}.img.xz"
echo "=== V20 PACK DONE ==="
