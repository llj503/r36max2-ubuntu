#!/bin/bash
# k72-recon.sh - download 7.2.8, unpack, and find out *before* building whether
# this board can move off 6.12.79: is the RK3326 base + our patch layers + the
# two out-of-tree drivers still going to work?
set -uo pipefail
KVER=7.2.8
D=/root/r36
TAR=$D/dl/linux-$KVER.tar.xz
mkdir -p "$D/dl"

echo "=== [1/6] download ==="
if [ ! -s "$TAR" ]; then
  curl -fL --retry 3 -o "$TAR" "https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-$KVER.tar.xz" || {
    echo "download failed"; exit 1; }
fi
ls -l "$TAR"
sha256sum "$TAR" | tee "$D/dl/linux-$KVER.tar.xz.sha256"

echo "=== [2/6] unpack ==="
[ -d "$D/linux-$KVER" ] || tar -C "$D" -xf "$TAR"
du -sh "$D/linux-$KVER"

cd "$D/linux-$KVER" || exit 1
echo "=== [3/6] what does mainline already have for RK3326? ==="
echo "--- rk3326/px30 dts:"
ls arch/arm64/boot/dts/rockchip/ | grep -E "rk3326|px30" | head -20
echo "--- joypad / handheld input drivers:"
ls drivers/input/joystick/ | grep -iE "anbernic|rgb20|odroid|game|joypad|xiao" | head
grep -rl "rocknix\|retrogame" drivers/input/ 2>/dev/null | head -5
echo "--- panel drivers used by our dts:"
grep -E "CONFIG_DRM_PANEL_SIMPLE|CONFIG_DRM_PANEL_ODROID|generic" drivers/gpu/drm/panel/Makefile 2>/dev/null | head -5
ls drivers/gpu/drm/panel/ | grep -iE "generic|simple" | head

echo "=== [4/6] do the three Rocknix patch layers apply to $KVER? ==="
for layer in patches patches-mainline dts; do
  d=/mnt/e/ubuntu/build/rocknix/$layer
  [ -d "$d" ] || { echo "  $layer: (no such dir)"; continue; }
  ok=0; bad=0; bads=""
  for p in "$d"/*.patch; do
    [ -e "$p" ] || continue
    if patch -p1 --dry-run -s -i "$p" >/dev/null 2>&1; then
      ok=$((ok+1))
    else
      bad=$((bad+1)); bads="$bads $(basename "$p")"
    fi
  done
  echo "  $layer: clean=$ok conflict=$bad"
  echo "$bads" | tr ' ' '\n' | head -8 | sed 's/^/      ! /'
done

echo "=== [5/6] out-of-tree drivers: do they even reference APIs we still have? ==="
echo "--- joypad source tree:"
ls /root/r36/joypad/src 2>/dev/null | head -8
echo "--- aic8800 source tree:"
ls /root/r36/wifi/aic8800dc-linux-patched-main 2>/dev/null | head -8

echo "=== [6/6] config handover ==="
cp -f /root/r36/linux-6.12.79/.config .config 2>/dev/null && \
  make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig 2>&1 | tail -12
grep -E "^(CONFIG_DRM_PANFROST|CONFIG_PMBUS|CONFIG_MFD_RK808|CONFIG_DRM_PANEL_SIMPLE|CONFIG_TOUCHSCREEN|CONFIG_REGULATOR_RK808|CONFIG_INPUT_JOYSTICK|CONFIG_JOYSTICK_ODROIDGO2|CONFIG_JOYSTICK_RGB20S|CONFIG_WLAN_VENDOR_AIC|CONFIG_MMC_DW_ROCKCHIP|CONFIG_ARM_CCI|CONFIG_DRM_ROCKCHIP)=" .config | sort
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- kernelversion
echo "=== recon done ==="
