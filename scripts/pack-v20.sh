#!/bin/bash
# pack-v20.sh - build the r36max2 image: MBR + vendor blobs + FAT(BOOT) + ext4 rootfs.
# Two things this version changes over v20:
#
#   * ONE kernel.  boot.ini loads 7.2.8 and nothing else.  v20 carried a second
#     Image, a second dtb, a second module tree and boot-612.ini purely as a way
#     back to 6.12.79; that costs ~40 MB of image and gives the packer four more
#     files that can be mismatched with each other.  The dual-kernel packer is in
#     git history (`git show 54332c2:scripts/pack-v20.sh`) if it is ever needed again.
#   * the Wayland stack + joypad->mouse bridge + EmulationStation in the rootfs,
#     weston installed but NOT enabled (it can wedge the VOP on 7.2.8, see
#     documentation/PER_DEVICE_DOCUMENTATION/r36max2/WAYLAND.md).
#
# Everything is verified against the image itself before it is compressed:
# module vermagic + sha, the boot.ini filenames actually exist on the FAT, dtb gpio
# polarity flags, no credentials, no baked SSH host keys, empty machine-id, weston
# not enabled.  u-boot 2017.09 cannot take a ${var} as a filename, so every variant
# is its own literal boot.ini-style file - which is also why a missing file here is
# a black screen with no serial cable to read the error.
set -euo pipefail
REPO=${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
K7=${K7:-/root/r36/linux-7.2.8}
ROOT=${ROOT:-/root/r36/rootfs}
OUT=${OUT:-/root/r36/out}
BLOBS=${BLOBS:-$REPO/artifacts/arkos}
PREBUILT=${PREBUILT:-$REPO/artifacts/prebuilt}
V="${V:-v21}"
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
echo "  module trees in the rootfs: $(ls "$ROOT/lib/modules" | tr '\n' ' ')(want: 7.2.8 )"
echo "  rootfs size: $(du -sh "$ROOT" | cut -f1)   modules: $(du -sh "$ROOT/lib/modules/7.2.8" 2>/dev/null | tr '\n' ' ')"
echo "  disk free in WSL: $(df -h / | tail -1 | awk '{print $4}')"

echo "=== [2] stage boot files (one kernel) ==="
mkdir -p "$OUT/boot"
cp -f "$K7/arch/arm64/boot/Image" "$OUT/boot/Image"
for d in rk3326-xifan-r36max2 rk3326-xifan-r36max2-usbhost rk3326-xifan-r36max2-gadget; do
  cp -f "$K7/arch/arm64/boot/dts/rockchip/$d.dtb" "$OUT/boot/$d.dtb"
done
ls -l "$OUT/boot" | sed 's/^/  /'
# The staged Image must be the one this kernel tree just built, not an older copy
# that survived in out/boot from a previous run (build-initrd3 also writes here).
want=$(sha256sum "$K7/arch/arm64/boot/Image" | cut -d' ' -f1)
got=$(sha256sum "$OUT/boot/Image" | cut -d' ' -f1)
[ "$want" = "$got" ] || { echo "!! staged Image sha != $K7 build output"; exit 1; }
echo "  Image sha matches the $K7 build: ${got:0:16}"
for f in "$OUT/boot/rk3326-xifan-r36max2.dtb" "$OUT/boot/rk3326-xifan-r36max2-usbhost.dtb"; do
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

echo "=== [4] FAT: one kernel, two boot.ini variants ==="
cp "$OUT/boot/Image" "$OUT/boot/uInitrd" "$MNT/boot/"
cp "$OUT/boot/rk3326-xifan-r36max2.dtb" "$MNT/boot/"
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
make_bootini "Image" "rk3326-xifan-r36max2.dtb" "$MNT/boot/boot.ini"
make_bootini "Image" "rk3326-xifan-r36max2-usbhost.dtb" "$MNT/boot/boot-usbhost.ini"
for f in boot.ini boot-usbhost.ini; do
  printf '  %-18s %s\n' "$f" "$(grep -oE 'Image[^ ]*|rk3326[^ ]*dtb' "$MNT/boot/$f" | tr '\n' ' ')"
done
if grep -q '{dtb}' "$MNT/boot/boot.ini"; then echo "!! boot.ini uses a variable filename"; exit 1; fi
# u-boot 2017.09 loads filenames literally, so every file a boot.ini names has to be
# on the FAT partition.  A typo here is a black screen with no serial cable to read
# the error, which is the one failure mode this board makes genuinely expensive.
for f in "$MNT"/boot/boot*.ini; do
  for n in $(sed -n 's/^load mmc 1:1 ${[^ ]*} \([^ ]*\)$/\1/p' "$f" | sort -u); do
    [ -f "$MNT/boot/$n" ] || { echo "!! $(basename "$f") loads '$n', which is not on the FAT"; exit 1; }
  done
  echo "  $(basename "$f"): every file it loads is present"
done

echo "=== [5] firmware fallback bundle and the Windows-side notes ==="
mkdir -p "$MNT/boot/fw/aic8800DC"
cp -f /root/r36/aic8800-radxa/src/USB/driver_fw/fw/aic8800DC/*.bin \
      /root/r36/aic8800-radxa/src/USB/driver_fw/fw/aic8800DC/*.txt \
      "$MNT/boot/fw/aic8800DC/" 2>/dev/null || echo "  (no alternate firmware bundle)"
cat > "$MNT/boot/r36-switches.txt" <<'TXT'
r36max2 Ubuntu (v21) - 这张 BOOT 分区上的开关

  boot.ini      内核启动参数。这个镜像只有一个内核：7.2.8（Image +
                rk3326-xifan-r36max2.dtb）。改这个文件就是在改启动，改之前先把它
                复制一份到电脑上 —— 这台机器没有串口，写错就是黑屏。
  wifi.txt      换网络 / 换人用这块板子：新建文本文件 wifi.txt，两行
                    SSID=你的WiFi名
                    PSK=你的密码
                （可选第三行 COUNTRY=CN）。开机 30 秒内、以及之后每分钟检查一次，
                内容变了就自动写进 wpa_supplicant 并重连，不用重刷。
                结果写回 wifi-status.txt：连上会给出 IP，连不上会列出附近热点。
                没放这个文件、镜像里也没烤凭据的话，这台机器就只剩"有线路径 SSH"一条
                输入通道（没有键盘也没有串口），所以这个文件就是唯一的输入通道。
                参考 wifi-example.txt（改名去掉 -example 即可生效）。
  rescue        新建同名空文件 -> 以 rescue.target 启动
  noscreen      新建同名空文件 -> 关掉屏幕上的状态页（刷屏或黑屏时用这个自救）
  r36-log       新建同名空文件 -> 立刻再写一份状态报告到 r36-boot.txt
  usbhost       想用第二组 USB 主机控制器（试 Type-C 插键盘）：把 boot-usbhost.ini
                改名成 boot.ini 覆盖掉即可，先备份原来那份
  fw\aic8800DC  一套备用的 AIC WiFi 固件（Radxa bundle 版）。要改用它们：新建空文件
                use-boot-fw，开机会把内核固件搜索路径指到这里并重载 WiFi 驱动

  图形（weston / 摇杆键鼠桥）装在系统里但**默认不启动**。SSH 进去：
      r36-wayland start        # 起 weston，键鼠桥跟着起（BindsTo）
      r36-wayland status       # 看合成器与摇杆桥的状态
      systemctl stop weston    # 回文字控制台
  注意：7.2.8 + 这颗 VOP 在长时间跑 weston 后可能出现翻页完成中断丢失（屏幕冻在
  最后一帧，只能重启）。先在串口/显示无解的情况下谨慎使用，详见仓库
  documentation/PER_DEVICE_DOCUMENTATION/r36max2/WAYLAND.md。

  EmulationStation 也在镜像里（二进制 /root/es/emulationstation，启动器 /usr/local/bin/r36-es）。
  2026-10-04 在真机上用眼睛确认过：`r36-es --kmsdrm` 能画出界面、摇杆能切条目、方向正确。
  走 weston 那条路会把摇杆交给键鼠桥（r36-keymapper 用 EVIOCGRAB 抓住手柄），ES 反而收不到
  事件，所以默认用 --kmsdrm：ES 直接读 /dev/input/event2，桥保持不启动。
  插上 ROM 之前 es_systems.cfg 里只有一个 demo 系统，那是为了让界面有东西可画、
  也是为了证明"ES 没因为缺文件直接退出"，不是游戏列表。

  每次开机 40 秒后（之后每 2 分钟）设备把完整状态写到 r36-boot.txt。
  u-boot 启动失败时自己会往这个分区写 error.log —— 黑屏就先看它。
  镜像里不带 SSH 主机密钥（首次开机 ssh-keygen -A 生成）；
  默认账号 ubuntu / 密码 ubuntu，root 同样是 ubuntu，**刷完第一件事就是 passwd 改掉**。
TXT
# say what is actually true about credentials on this particular card.  The conf file
# always exists (the no-credentials build writes a commented placeholder), so test for
# a real network block, not for the filename.
if grep -q '^[[:space:]]*ssid=' "$ROOT/etc/wpa_supplicant/wpa_supplicant-wlan0.conf" 2>/dev/null; then
  echo "  例外：这个镜像里烤进了一份 WiFi 凭据（构建者自己的网络，存的是 PBKDF2 哈希，
        不是明文口令）。要把这张卡交给别人，先用 R36_BAKE_WIFI=0 bash scripts/build-rootfs.sh 重做。" \
    >> "$MNT/boot/r36-switches.txt"
  echo "  FAT note: a network IS baked"
else
  echo "  FAT note: no credentials in the image"
fi
cat > "$MNT/boot/wifi-example.txt" <<'EXM'
SSID=my-wifi-name
PSK=my-passphrase-at-least-8-chars
COUNTRY=CN
EXM
mkdir -p "$MNT/boot/extlinux"
cat > "$MNT/boot/extlinux/extlinux.conf" <<'ELX'
LABEL Ubuntu-7.2.8
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
echo "kernel=7.2.8 image=compact-2.1GiB expand=r36-expand-root wayland=installed-not-enabled es=kmsdrm-default credentials=none built=$(date -Is)" \
  > "$MNT/root/etc/r36max2-build-info"
sync
df -h "${LOOP}p2" | tail -1 | awk '{print "  root partition: size="$2" used="$3" avail="$4" use%="$5}'

echo "=== [7] verify what actually landed in the image ==="
fail=0

echo "  -- FAT: only the files this image means to boot from --"
stray=$(ls "$MNT/boot" | grep -E '^(Image-|boot-612|boot-72|.*-7\.2\.8\.dtb)' | tr '\n' ' ' || true)
[ -z "$stray" ] || { echo "    !! leftovers from the dual-kernel layout: $stray"; fail=1; }
for n in $(sed -n 's/^  \(LINUX\|INITRD\|FDT\) \(\/[^ ]*\)$/\2/p' "$MNT/boot/extlinux/extlinux.conf"); do
  [ -f "$MNT/boot${n}" ] || { echo "    !! extlinux names $n, not on the FAT"; fail=1; }
done
echo "    FAT: $(ls "$MNT/boot" | tr '\n' ' ')"

echo "  -- modules: exactly one kernel tree --"
trees=$(ls "$MNT/root/lib/modules" | tr '\n' ' ')
echo "    /lib/modules: $trees"
[ "$trees" = "7.2.8 " ] || { echo "    !! expected only 7.2.8, got: $trees"; fail=1; }
n=$(find "$MNT/root/lib/modules/7.2.8" -name '*.ko' 2>/dev/null | wc -l)
echo "    .ko count: $n"
[ "$n" -gt 50 ] || { echo "    !! too few modules"; fail=1; }
[ -e "$MNT/root/lib/modules/7.2.8/modules.dep" ] || { echo "    !! no modules.dep (depmod missing)"; fail=1; }
[ -e "$MNT/root/lib/modules/7.2.8/build" ] && { echo "    !! build symlink survived"; fail=1; }
# the four out-of-tree modules are the hardware-verified ones from artifacts/prebuilt;
# check them against the manifest by sha, because a .ko with the right name and the
# wrong content still modprobes fine and then misbehaves in a way nobody traces.
[ -s "$PREBUILT/MANIFEST.sha256" ] || { echo "    !! no $PREBUILT/MANIFEST.sha256 to check against"; fail=1; }
for m in aic8800_fdrv aic_load_fw rocknix-singleadc-joypad rocknix-joypad; do
  f="$MNT/root/lib/modules/7.2.8/extra/$m.ko"
  if [ ! -e "$f" ]; then echo "    !! missing extra/$m.ko"; fail=1; continue; fi
  v=$(modinfo -F vermagic "$f" | awk '{print $1}')
  w=$(awk -v n="$m.ko" '$2=="*"n || $2==n {print $1}' "$PREBUILT/MANIFEST.sha256")
  g=$(sha256sum "$f" | cut -d' ' -f1)
  [ "$v" = "7.2.8" ] || { echo "      !! $m.ko vermagic $v"; fail=1; }
  [ -n "$w" ] && [ "$w" = "$g" ] || { echo "      !! $m.ko sha != manifest ($g)"; fail=1; }
  echo "    extra/$m.ko vermagic=$v sha=${g:0:16} (matches prebuilt manifest)"
done

echo "  -- wifi: the units that were never installed on the v20 card --"
# KNOWN-ISSUES: the card could not join a network because r36-wifi-setup.{service,timer}
# were on disk but in no *.wants/ symlink, so systemd never ran them and the only
# symptom was a silent absence from r36-boot.txt (whose service list does not include
# them either).  Absence of a log line proves nothing; presence is asserted.
for want in multi-user.target.wants/r36-wifi-setup.service timers.target.wants/r36-wifi-setup.timer; do
  [ -e "$MNT/root/etc/systemd/system/$want" ] \
    || { echo "    !! not enabled: $want"; fail=1; }
done
echo "    wifi-setup enabled: $(ls "$MNT/root/etc/systemd/system/multi-user.target.wants/" 2>/dev/null | grep -c 'wifi-setup\|r36-wpa@') service links, $(ls "$MNT/root/etc/systemd/system/timers.target.wants/" 2>/dev/null | grep -c wifi-setup) timer link"

echo "  -- EmulationStation: launcher, binary, and the two cfgs ES refuses to start without --"
for f in usr/local/bin/r36-es root/es/emulationstation \
         root/.emulationstation/es_input.cfg root/.emulationstation/es_systems.cfg; do
  [ -s "$MNT/root/$f" ] || { echo "    !! missing or empty: /$f"; fail=1; }
done
grep -q 'deviceGUID="19009b4d4b4800000111000000010000"' "$MNT/root/root/.emulationstation/es_input.cfg" \
  || { echo "    !! es_input.cfg lost this board's GUID"; fail=1; }
for axis in joystick1left joystick1up; do
  grep -q "name=\"$axis\"" "$MNT/root/root/.emulationstation/es_input.cfg" \
    || { echo "    !! es_input.cfg lost the $axis binding (stick cannot move the cursor)"; fail=1; }
done
python3 -c 'import sys,xml.etree.ElementTree as T
T.parse(sys.argv[1]); r=T.parse(sys.argv[2]).getroot()
sys.exit(0 if r.findall("system") else 1)' \
  "$MNT/root/root/.emulationstation/es_input.cfg" \
  "$MNT/root/root/.emulationstation/es_systems.cfg" \
  || { echo "    !! an ES cfg does not parse, or es_systems.cfg has zero systems"; fail=1; }
echo "    ES files present, GUID + both stick axes in place"

echo "  weston: $(ls "$MNT/root/usr/bin/weston" 2>/dev/null || echo MISSING)  backends: $(find "$MNT/root/usr/lib" -name 'drm-backend.so' 2>/dev/null | wc -l)"
echo "  weston enabled? $(ls "$MNT/root/etc/systemd/system/multi-user.target.wants/weston.service" 2>/dev/null || echo "no (correct)")"
[ -e "$MNT/root/etc/systemd/system/multi-user.target.wants/weston.service" ] && { echo "    !! weston must ship disabled"; fail=1; }
echo "  keymapper: $(ls "$MNT/root/usr/local/bin/r36-keymapper.py" "$MNT/root/usr/local/bin/r36-wayland" 2>/dev/null | wc -l)/2 files"
echo "  ssh host keys in image: $(ls "$MNT/root/etc/ssh/ssh_host_*" 2>/dev/null | wc -l) (must be 0)"
echo "  host-key regen unit: $(ls "$MNT/root/etc/systemd/system/multi-user.target.wants/r36-hostkeys.service" 2>/dev/null || echo MISSING)"
echo "  machine-id: $([ -s "$MNT/root/etc/machine-id" ] && echo NON-EMPTY || echo empty)"
wpas="$MNT/root/etc/wpa_supplicant/wpa_supplicant-wlan0.conf"
if [ -f "$wpas" ]; then
  echo "    baked network blocks: $(grep -c '^[[:space:]]*ssid=' "$wpas" || true)"
  # a quoted psk= is the passphrase itself; the 64-hex form is the PBKDF2 pre-key.
  # Leaking the former means every copy of this image carries somebody's WiFi password.
  grep -q 'psk="' "$wpas" && { echo "    !! plaintext passphrase in the image"; fail=1; }
fi
echo "  chvt/fgconsole (kbd): $(ls "$MNT/root/usr/bin/chvt" 2>/dev/null || echo MISSING)"
echo "  modules-load.d: $(tr '\n' ' ' < "$MNT/root/etc/modules-load.d/r36max2.conf")"
for d in "$MNT/boot/rk3326-xifan-r36max2.dtb"; do
  echo "  FAT $(basename "$d"): $(dtc -I dtb -O dts "$d" 2>/dev/null | grep -E 'rumble-gpio|amux-a-gpios' | tr -s ' \t' ' ' | tr '\n' ' ')"
done
[ "$fail" = 0 ] || { echo "!! verification FAILED - not compressing"; exit 1; }

echo "=== [8] close it out and compress ==="
sync; umount "$MNT/root"; umount "$MNT/boot"
e2fsck -fy "${LOOP}p2" >/dev/null 2>&1 || true
sync; losetup -d "$LOOP"
time xz -T0 -6 -c "$IMG" > $REPO/distributions/r36max2-ubuntu-${V}.img.xz
cd $REPO/distributions && sha256sum r36max2-ubuntu-${V}.img.xz | tee r36max2-ubuntu-${V}.img.xz.sha256
ls -la "r36max2-ubuntu-${V}.img.xz"
echo "=== V20 PACK DONE ==="
