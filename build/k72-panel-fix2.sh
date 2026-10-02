#!/bin/bash
# k72-panel-fix2.sh - the real reason DRM_PANEL_GENERIC_DSI never appeared: my
# Kconfig entry said `depends on MIPI_DSI`, but the symbol is named
# DRM_MIPI_DSI.  Fix the dependency, turn it on, rebuild the panel dir + Image.
# Also check whether the legacy integer GPIO API the joypad driver uses still
# exists in 7.2 (that decides how the joypad port has to be done).
set -uo pipefail
K=/root/r36/linux-7.2.8
X=ARCH=arm64
CROSS=CROSS_COMPILE=aarch64-linux-gnu-
cd "$K" || exit 1

echo "=== fix the dependency line ==="
sed -i 's/^\tdepends on OF \&\& MIPI_DSI$/\tdepends on OF \&\& DRM_MIPI_DSI/' drivers/gpu/drm/panel/Kconfig
grep -A3 "^config DRM_PANEL_GENERIC_DSI" drivers/gpu/drm/panel/Kconfig | sed 's/^/  /'

./scripts/config --enable DRM_PANEL_GENERIC_DSI
make $X $CROSS olddefconfig 2>&1 | grep -viE "^  (HOSTCC|HOSTLD|GEN|CALL|LEX|YACC|BISON| flex)" | tail -4
echo "  result: $(grep -m1 '^CONFIG_DRM_PANEL_GENERIC_DSI' .config || echo STILL-ABSENT)"

echo "=== rebuild panel dir + Image ==="
make $X $CROSS -j"$(nproc)" Image 2>&1 | grep -E "error|LD|Image|wall" | tail -8
ls -l arch/arm64/boot/Image | sed 's/^/  /'
make $X $CROSS INSTALL_MOD_PATH=/root/r36/out72 modules_install 2>&1 | tail -2
echo "  built-in panel object: $(ls -l drivers/gpu/drm/panel/panel-generic-dsi.o 2>/dev/null | awk '{print $5}') bytes"

echo "=== legacy integer GPIO API in 7.2? ==="
for s in gpio_get_value_cansleep gpio_set_value gpio_is_valid devm_gpio_request_one gpio_to_desc; do
  n=$(grep -rl "$s" include/linux/gpio.h include/asm-generic/gpio.h include/linux/gpio/consumer.h 2>/dev/null | wc -l)
  printf '  %-26s declared in %s header(s)\n' "$s" "$n"
done
echo "=== of_gpio helpers still anywhere? ==="
grep -rn "int of_get_named_gpio\b\|#define of_get_named_gpio\b" include/linux/ drivers/of/ drivers/gpio/ 2>/dev/null | head -4 | sed 's/^/  /'
echo "=== fix2 done ==="
