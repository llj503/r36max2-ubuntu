#!/bin/bash
# k72-recon2.sh - the decisive question for moving to 7.2.8 is not whether the
# kernel builds, it's whether the two out-of-tree drivers (joypad, AIC8800) and
# our board dts survive.  Check mainline contents, prepare the tree for module
# builds, then actually try compiling both drivers against 7.2.8.
set -uo pipefail
K=/root/r36/linux-7.2.8
T=/root/r36/k72test
X=ARCH=arm64
CROSS=CROSS_COMPILE=aarch64-linux-gnu-
mkdir -p "$T"
cd "$K" || exit 1

echo "=== [1] what does mainline 7.2.8 ship for handhelds / our chip? ==="
echo "--- rk3326 boards:"
ls arch/arm64/boot/dts/rockchip/ | grep "^rk3326" | head -20
echo "--- input/joystick drivers:"
ls drivers/input/joystick/ | grep -vE "Makefile|Kconfig" | tr '\n' ' '; echo
echo "--- aic8800 upstreamed?"; ls drivers/net/wireless/ | tr '\n' ' '; echo
grep -rli "aic8800" drivers/net/wireless/ 2>/dev/null | head -3 || echo "  (no aic8800 in tree)"
echo "--- does the generic DSI panel driver we rely on exist?"
ls drivers/gpu/drm/panel/ | grep -iE "generic|desc" | head -5
grep -rn "panel_description" drivers/gpu/drm/ include/video/ 2>/dev/null | head -3 || echo "  (no panel_description property)"

echo "=== [2] compatible strings used by our board dts, present in 7.2.8? ==="
DTS=/root/r36/linux-6.12.79/arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dts
grep -ohE 'compatible = "[^"]+"' "$DTS" | sed -E 's/compatible = "//;s/"//' | sort -u | while read -r c; do
  if grep -rqF "\"$c\"" drivers/ 2>/dev/null; then
    echo "  ok       $c"
  else
    echo "  MISSING  $c"
  fi
done

echo "=== [3] make modules_prepare (needed before external builds) ==="
make $X $CROSS modules_prepare 2>&1 | tail -4

echo "=== [4] joypad driver vs 7.2.8 ==="
rm -rf "$T/joypad"; cp -r /root/r36/joypad/src "$T/joypad"
cd "$T/joypad" && make clean >/dev/null 2>&1
make -C "$K" M="$T/joypad" $X $CROSS DEVICE=RK3326 modules 2>&1 | grep -E "error|Error|warning: (implicit|passing)|\.ko" | head -25
echo "  result: $(ls "$T/joypad"/*.ko 2>/dev/null | tr '\n' ' ' || echo NO .ko)"

echo "=== [5] AIC8800 driver vs 7.2.8 ==="
rm -rf "$T/wifi"; cp -r /root/r36/wifi/aic8800dc-linux-patched-main "$T/wifi"
cd "$T/wifi" && make -C drivers/aic8800 clean >/dev/null 2>&1
make -C "$T/wifi" -C drivers/aic8800 KDIR="$K" $X $CROSS 2>&1 | grep -E "error:|Error|\.ko" | head -25
echo "  result: $(find "$T/wifi" -name "*.ko" -printf "%f " 2>/dev/null)${x:-}"
echo "=== recon2 done ==="
