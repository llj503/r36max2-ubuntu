#!/bin/bash
# v20-stage72.sh - collect the 7.2.8 kernel-side artifacts into one place so the
# image build has a single, checked source: Image, dtbs, modules tree, and the
# four out-of-tree .ko (AIC WiFi for 7.2.8, gpiod joypad for 7.2.8).
set -uo pipefail
K7=/root/r36/linux-7.2.8
OUT=/root/r36/out
OUT72=/root/r36/out72
AJ=/mnt/e/ubuntu/artifacts/joypad
AA=/mnt/e/ubuntu/artifacts/aic72

echo "=== [1] kernel + dtbs ==="
mkdir -p "$OUT/boot"
sha256sum "$K7/arch/arm64/boot/Image" | cut -c1-24 | sed 's/^/  Image-7.2.8 (want 6717e7fe): /'
cp -f "$K7/arch/arm64/boot/Image" "$OUT/boot/Image-7.2.8"
for d in rk3326-xifan-r36max2 rk3326-xifan-r36max2-usbhost rk3326-xifan-r36max2-gadget; do
  cp -f "$K7/arch/arm64/boot/dts/rockchip/$d.dtb" "$OUT/boot/$d-7.2.8.dtb"
done
cp -f "$K7/arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dtb" "$OUT/boot/rk3326-xifan-r36max2-7.2.8.dtb"
ls -l "$OUT/boot" | sed 's/^/  /'
echo "  dtb sha (want e7d56108 for the polarity-fixed one): $(sha256sum "$OUT/boot/rk3326-xifan-r36max2-7.2.8.dtb" | cut -c1-8)"
dtc -I dtb -O dts "$OUT/boot/rk3326-xifan-r36max2-7.2.8.dtb" 2>/dev/null |
  grep -E "amux-a-gpios|amux-en-gpios|rumble-gpio" | sed 's/^/    /'

echo
echo "=== [2] the 6.12 dtb in the staging dir must ALSO be the new one (gpiod flags are harmless for the legacy .ko, but keeping them identical avoids surprises) ==="
echo "  current: $(sha256sum "$OUT/boot/rk3326-xifan-r36max2.dtb" | cut -c1-8)  (new 6.12 build is 26ffbec7)"
cp -f /root/r36/linux-6.12.79/arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dtb "$OUT/boot/rk3326-xifan-r36max2.dtb"
cp -f /root/r36/linux-6.12.79/arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2-usbhost.dtb "$OUT/boot/" 2>/dev/null
echo "  after  : $(sha256sum "$OUT/boot/rk3326-xifan-r36max2.dtb" | cut -c1-8)"

echo
echo "=== [3] the 7.2.8 modules tree ==="
du -sh "$OUT72/lib/modules/7.2.8" 2>/dev/null | sed 's/^/  /'
ls "$OUT72/lib/modules/7.2.8/extra" 2>/dev/null | sed 's/^/  extra: /'
echo "  build dir still has the freshly built ones?"
ls -l /root/r36/wifi/drivers/aic8800/aic8800_fdrv/aic8800_fdrv.ko \
      /root/r36/wifi/drivers/aic8800/aic_load_fw/aic_load_fw.ko 2>/dev/null | sed 's/^/    /'
ls -l "$AJ"/*.ko 2>/dev/null | sed 's/^/    /'

echo
echo "=== [4] stage the four out-of-tree .ko for 7.2.8 ==="
mkdir -p "$AA" "$OUT72/lib/modules/7.2.8/extra"
for src in /root/r36/wifi/drivers/aic8800/aic8800_fdrv/aic8800_fdrv.ko \
           /root/r36/wifi/drivers/aic8800/aic_load_fw/aic_load_fw.ko; do
  [ -e "$src" ] && cp -f "$src" "$AA/" && echo "  copied $(basename "$src")"
done
cp -f "$AJ/rocknix-singleadc-joypad-7.2.8.ko" "$OUT72/lib/modules/7.2.8/extra/rocknix-singleadc-joypad.ko"
cp -f "$AJ/rocknix-joypad-7.2.8.ko"           "$OUT72/lib/modules/7.2.8/extra/rocknix-joypad.ko"
[ -e "$AA/aic8800_fdrv.ko" ] && cp -f "$AA/aic8800_fdrv.ko" "$OUT72/lib/modules/7.2.8/extra/"
[ -e "$AA/aic_load_fw.ko" ]  && cp -f "$AA/aic_load_fw.ko"  "$OUT72/lib/modules/7.2.8/extra/"
echo "  final extra dir:"
for f in "$OUT72/lib/modules/7.2.8/extra"/*.ko; do
  echo "    $(basename "$f"): vermagic=$(modinfo -F vermagic "$f" 2>&1 | head -1)"
done
echo "=== staging done ==="
