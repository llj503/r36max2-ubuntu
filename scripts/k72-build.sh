#!/bin/bash
# k72-build.sh - force on the two carried-over symbols, then build Image + dtbs
# + modules for 7.2.8 and stage them separately from the working 6.12.79 set.
set -uo pipefail
K=/root/r36/linux-7.2.8
OUT=/root/r36/out72
X=ARCH=arm64
CROSS=CROSS_COMPILE=aarch64-linux-gnu-
cd "$K" || exit 1

echo "=== nproc: $(nproc), free: $(free -g | awk '/Mem/{print $2" GiB"}') ==="
./scripts/config --enable INPUT_POLLDEV --enable DRM_PANEL_GENERIC_DSI
make $X $CROSS olddefconfig 2>&1 | grep -E "warning|Error" | head -5
for c in CONFIG_INPUT_POLLDEV CONFIG_DRM_PANEL_GENERIC_DSI; do
  echo "  $(grep -m1 "^$c" .config || echo "$c STILL ABSENT")"
done

echo "=== build Image + dtbs + modules ==="
/usr/bin/time -f "build wall=%es maxrss=%MkB" make $X $CROSS -j"$(nproc)" Image dtbs modules 2>&1 | \
  grep -E "error:|Error|warning:|\.ko|Image|wall=" | tail -40
echo "=== artifacts ==="
ls -l arch/arm64/boot/Image arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dtb 2>&1
mkdir -p "$OUT"
make $X $CROSS INSTALL_MOD_PATH="$OUT" modules_install 2>&1 | tail -3
du -sh "$OUT" 2>/dev/null
find "$OUT" -name "*.ko" | sed 's|.*/|  |' | head -20
echo "=== build done ==="
