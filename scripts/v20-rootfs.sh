#!/bin/bash
# v20-rootfs.sh - put the 7.2.8 module tree into the staging rootfs, with the
# out-of-tree .ko that were verified on hardware, and prove it with depmod +
# modprobe --dry-run inside the chroot.
#
# One kernel only, since v21.  The dual-kernel image carried two module trees and
# a second dtb purely as a way back to 6.12.79; that path is now in git history
# (`git show 54332c2:scripts/pack-v20.sh`) and 6.12 in the image only doubled the
# chance of shipping a module that loads into the wrong kernel.
#
# Two traps this script exists to avoid:
#   * modules_install leaves `build` and `source` symlinks into the 1.8 GB kernel
#     tree; if they survive into the image every card gets a dangling multi-GB
#     symlink (and anything copying with -r follows them).
#   * a tree can only be built for one kernel at a time, so "which .ko is this"
#     must be answered by vermagic + sha, never by the filename or the mtime.
set -uo pipefail
REPO=${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
R=${R:-/root/r36/rootfs}
OUT=${OUT:-/root/r36/out}
OUT72=${OUT72:-/root/r36/out72}
WSLNS=$(awk '/^nameserver/{print $2; exit}' /etc/resolv.conf)

echo "=== [1] 7.2.8 module tree ==="
rm -rf "$R/lib/modules/7.2.8"
cp -a "$OUT72/lib/modules/7.2.8" "$R/lib/modules/"
rm -f "$R/lib/modules/7.2.8/build" "$R/lib/modules/7.2.8/source"
# Whatever the build tree happens to have in extra/ is not trusted: only the
# manifest-checked .ko from artifacts/prebuilt may reach a card, so start empty.
rm -rf "$R/lib/modules/7.2.8/extra"
echo "  staged $(find "$R/lib/modules/7.2.8" -name '*.ko' | wc -l) .ko, $(du -sh "$R/lib/modules/7.2.8" | cut -f1)"
echo "  build/source symlinks left: $(find "$R/lib/modules/7.2.8" -maxdepth 1 -name build -o -maxdepth 1 -name source | wc -l)"

echo
echo "=== [2] out-of-tree .ko for 7.2.8 (each one proven on the card) ==="
mkdir -p "$R/lib/modules/7.2.8/extra"
# 7.2.8 的 joypad / aic8800 模块目前只能复用已验证实机的那份（基底源码随 E: 盘丢了，
# ROCKNIX 当前 pin 的 rev 与我们那 5 个补丁不匹配，见 git 历史）。所以这里不是"装上就算"，
# 而是逐个校 sha256 与 vermagic：任何一个不匹配就停，绝不悄悄发出一个模块失配的镜像。
PREBUILT=${PREBUILT:-$REPO/artifacts/prebuilt}
[ -s "$PREBUILT/MANIFEST.sha256" ] || { echo "!! no $PREBUILT/MANIFEST.sha256 - 先把实测过的 .ko 和清单放进来"; exit 1; }
# 整份清单一次校完。不逐个 grep 文件名：那种写法在 "./name" 与 "name" 之间极易写错，
# 而一旦错成"永远失败"，下一步往往就是有人把这行检查删掉——那比没有检查更糟。
( cd "$PREBUILT" && sha256sum -c --quiet MANIFEST.sha256 ) \
  || { echo "!! artifacts/prebuilt 与 MANIFEST.sha256 不一致，拒绝出镜像"; exit 1; }
for k in aic8800_fdrv aic_load_fw rocknix-singleadc-joypad rocknix-joypad; do
  src="$PREBUILT/$k.ko"
  [ -f "$src" ] || { echo "!! 清单里没有 $k.ko"; exit 1; }
  vm=$(modinfo -F vermagic "$src" 2>/dev/null | cut -d' ' -f1)
  [ "$vm" = "7.2.8" ] || { echo "!! $k.ko vermagic=$vm, 不是 7.2.8"; exit 1; }
  cp -f "$src" "$R/lib/modules/7.2.8/extra/$k.ko"
  echo "  ok $k.ko vermagic=$vm"
done
(chroot "$R" depmod -a 7.2.8 2>/dev/null || depmod -a -b "$R" 7.2.8) || echo "  !! depmod failed"
echo "  prebuilt 7.2.8 modules installed and verified against $PREBUILT"
for f in "$R"/lib/modules/7.2.8/extra/*.ko; do
  echo "  $(basename "$f"): $(stat -c%s "$f") B vermagic=$(modinfo -F vermagic "$f" | awk '{print $1}') $(sha256sum "$f" | cut -c1-16)"
done

echo
echo "=== [3] no other kernel's modules may be in this rootfs ==="
# A second tree here would not be a safety net, it would be a way to ship a .ko
# that nothing loads: boot.ini names one kernel and one dtb.
for d in "$R"/lib/modules/*; do
  [ -d "$d" ] || continue
  echo "  $(basename "$d"): $(find "$d" -name '*.ko' | wc -l) .ko"
  [ "$(basename "$d")" = "7.2.8" ] || { echo "  !! a second kernel tree survived: $d"; exit 1; }
done

echo
echo "=== [4] chroot housekeeping + depmod ==="
mount -t proc proc "$R/proc" 2>/dev/null || true
printf 'nameserver %s\n' "$WSLNS" > "$R/etc/resolv.conf"
printf '#!/bin/sh\nexit 101\n' > "$R/usr/sbin/policy-rc.d"; chmod 755 "$R/usr/sbin/policy-rc.d"
chroot "$R" /usr/bin/env depmod -a 7.2.8  && echo "  depmod 7.2.8 ok"
for m in aic8800_fdrv aic_load_fw rocknix_singleadc_joypad; do
  out=$(chroot "$R" /usr/bin/env modprobe -n -S 7.2.8 "$m" 2>&1)
  echo "  modprobe -n $m : ${out:-OK}"
done
echo "  modules-load.d: $(tr '\n' ' ' < "$R/etc/modules-load.d/r36max2.conf")"

echo
echo "=== [5] the boot files the packer will copy ==="
ls -l "$OUT/boot" | sed 's/^/  /'
echo "  polarity check (want amux-a flags 0x00, amux-en 0x01, rumble 0x00):"
for f in "$OUT/boot/rk3326-xifan-r36max2.dtb" "$OUT/boot/rk3326-xifan-r36max2-usbhost.dtb"; do
  if [ ! -e "$f" ]; then echo "    !! $f missing - run scripts/v20-stage72.sh first"; exit 1; fi
done
for f in "$OUT/boot/rk3326-xifan-r36max2.dtb" "$OUT/boot/rk3326-xifan-r36max2-usbhost.dtb"; do
  echo "    $(basename "$f"):"
  dtc -I dtb -O dts "$f" 2>/dev/null | grep -E "amux-a-gpios|amux-en-gpios|rumble-gpio" | sed 's/^/        /'
done
rm -f "$R/usr/sbin/policy-rc.d"
echo "=== rootfs staging done ==="
