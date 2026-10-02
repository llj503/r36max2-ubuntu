#!/bin/bash
# k72-prepare.sh - build the 7.2.8 tree for this board: apply only the patches
# that still apply (the 13 conflicting panfrost ones are dropped because their
# features are upstream in 7.2), carry the two Rocknix-only drivers we still
# need (panel-generic-dsi), and wire our board dts in.
set -uo pipefail
K=/root/r36/linux-7.2.8
R=/mnt/e/ubuntu/build/rocknix
X=ARCH=arm64
CROSS=CROSS_COMPILE=aarch64-linux-gnu-
cd "$K" || exit 1

echo "=== which patches mention the APIs we care about? ==="
for pat in polldev gpiolib pwm adc-keys; do
  echo "  --- $pat:"
  grep -rl "$pat" "$R"/patches/*.patch "$R"/patches-mainline/*.patch 2>/dev/null |
    sed 's|.*/|      |' | head -6
done

echo "=== apply layer: patches (skipping conflicts) ==="
applied=0; skipped=0
for p in "$R"/patches/*.patch; do
  [ -e "$p" ] || continue
  if patch -p1 --dry-run -s -i "$p" >/dev/null 2>&1; then
    patch -p1 -s -i "$p" >/dev/null 2>&1 && applied=$((applied+1)) || { echo "  APPLY FAILED at run time: $(basename "$p")"; skipped=$((skipped+1)); }
  else
    skipped=$((skipped+1))
  fi
done
echo "  applied=$applied skipped=$skipped"

echo "=== apply layer: patches-mainline (skipping conflicts) ==="
for p in "$R"/patches-mainline/*.patch; do
  [ -e "$p" ] || continue
  if patch -p1 --dry-run -s -i "$p" >/dev/null 2>&1; then
    patch -p1 -s -i "$p" >/dev/null 2>&1 && echo "  ok: $(basename "$p")"
  else
    echo "  CONFLICT (left out): $(basename "$p")"
  fi
done

echo "=== carry the Rocknix-only panel driver ==="
mkdir -p drivers/gpu/drm/panel
cp -f "$R/drivers/panel-generic-dsi.c" drivers/gpu/drm/panel/ 2>/dev/null && echo "  panel-generic-dsi.c copied"
grep -q panel-generic-dsi drivers/gpu/drm/panel/Makefile || \
  echo 'obj-$(CONFIG_DRM_PANEL_GENERIC_DSI) += panel-generic-dsi.o' >> drivers/gpu/drm/panel/Makefile
grep -q DRM_PANEL_GENERIC_DSI drivers/gpu/drm/panel/Kconfig || cat >> drivers/gpu/drm/panel/Kconfig <<'KC'

config DRM_PANEL_GENERIC_DSI
	tristate "Generic DSI panel with a textual panel_description"
	depends on OF && MIPI_DSI
	help
	  Carried over from Rocknix: matches a DSI panel by the init sequence
	  description string in the DT instead of a hard-coded panel list.
KC

echo "=== install our board dts ==="
cp -f /mnt/e/ubuntu/board/rk3326-xifan-r36max2.dts \
      /mnt/e/ubuntu/board/rk3326-xifan-r36max2-usbhost.dts \
      /mnt/e/ubuntu/board/rk3326-xifan-r36max2-gadget.dts \
      /mnt/e/ubuntu/board/rk3326-xifan-r36max2-dram-timing.dtsi \
      arch/arm64/boot/dts/rockchip/
M=arch/arm64/boot/dts/rockchip/Makefile
for d in rk3326-xifan-r36max2 rk3326-xifan-r36max2-usbhost rk3326-xifan-r36max2-gadget; do
  grep -q "$d.dtb" "$M" || echo "dtb-\$(CONFIG_ARCH_ROCKCHIP) += $d.dtb" >> "$M"
done
grep -c xifan "$M" | sed 's/^/  Makefile lines mentioning xifan: /'

echo "=== config ==="
make $X $CROSS olddefconfig 2>&1 | grep -E "warning|Error" | head -5
for c in CONFIG_DRM_PANEL_GENERIC_DSI CONFIG_INPUT_POLLDEV CONFIG_TOUCHSCREEN_ATMEL_MXT CONFIG_DRM_PANEL_SIMPLE; do
  echo "  $(grep -m1 "^$c" .config || echo "$c (not in Kconfig at all)")"
done

echo "=== dtbs only, to prove the board dts still compiles against 7.2 ==="
make $X $CROSS dtbs 2>&1 | grep -E "DTC|Error|error|warning:" | tail -15
ls -l arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dtb 2>&1
echo "=== prepare done ==="
