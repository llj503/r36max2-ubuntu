#!/bin/bash
# k72-drivers.sh - after the full 7.2.8 build (so Module.symvers is real):
#  1. fix the panel Kconfig placement and rebuild that one directory
#  2. compile the AIC8800 WiFi modules against the full tree
#  3. compile the rocknix joypad module and show exactly what the missing
#     gpiolib-revert patch costs us
set -uo pipefail
K=/root/r36/linux-7.2.8
OUT=/root/r36/out72
T=/root/r36/k72test
X=ARCH=arm64
CROSS=CROSS_COMPILE=aarch64-linux-gnu-

echo "=== [1] panel driver Kconfig fix + incremental build ==="
bash /mnt/e/ubuntu/scripts/k72-panel-fix.sh | tail -12
cd "$K" || exit 1
./scripts/config --enable DRM_PANEL_GENERIC_DSI
make $X $CROSS olddefconfig 2>&1 | grep -E "warning|Error" | head -4
echo "  now: $(grep -m1 '^CONFIG_DRM_PANEL_GENERIC_DSI' .config || echo STILL-ABSENT)"
make $X $CROSS -j8 drivers/gpu/drm/panel/ 2>&1 | grep -E "error|CC|LD|\.ko" | tail -12
ls -l drivers/gpu/drm/panel/panel-generic-dsi.ko 2>&1 | sed 's/^/  /'
make $X $CROSS INSTALL_MOD_PATH="$OUT" modules_install 2>&1 | tail -2

echo "=== [2] AIC8800 WiFi vs 7.2.8 (full tree, real Module.symvers) ==="
rm -rf "$T/wifi"; cp -r /root/r36/wifi/aic8800dc-linux-patched-main "$T/wifi"
cd "$T/wifi/drivers/aic8800" && make clean >/dev/null 2>&1
make -C "$T/wifi/drivers/aic8800" KDIR="$K" $X $CROSS 2>&1 | \
  grep -E "error:|warning:.*implicit|undefined|ERROR|\.ko$" | head -30
echo "  built .ko:"; find "$T/wifi" -name "*.ko" -printf "    %p (%s bytes)\n" 2>/dev/null
cd "$K"

echo "=== [3] rocknix joypad vs 7.2.8 ==="
rm -rf "$T/joypad"; cp -r /root/r36/joypad/src "$T/joypad"
cd "$T/joypad" && make clean >/dev/null 2>&1
rm -f *.ko *.o *.mod *.mod.c Module.symvers modules.order 2>/dev/null
make -C "$K" M="$T/joypad" $X $CROSS DEVICE=RK3326 modules 2>&1 | \
  grep -E "error:|implicit declaration|undefined|\.ko" | head -30
echo "  built .ko:"; find "$T/joypad" -name "*.ko" -printf "    %p (%s bytes)\n" 2>/dev/null

echo "=== summary ==="
for f in "$K/drivers/gpu/drm/panel/panel-generic-dsi.ko" \
         "$T/wifi/drivers/aic8800/aic8800_fdrv/aic8800_fdrv.ko" \
         "$T/wifi/drivers/aic8800/aic_load_fw/aic_load_fw.ko" \
         "$T/joypad/rocknix-singleadc-joypad.ko"; do
  printf '  %-58s %s\n' "$(basename "$f")" "$([ -e "$f" ] && echo OK || echo MISSING)"
done
echo "=== drivers done ==="
