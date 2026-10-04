#!/bin/bash
# k72-diag2.sh - (1) did the MIPI_DSI symbol get renamed between 6.12 and 7.2
# (that would silently drop DSI host support in the new build), (2) does the
# joypad driver really need the legacy gpiolib internals or just an inline
# wrapper, (3) does include/linux/of_gpio.h still exist in 7.2?
set -uo pipefail
A=/root/r36/linux-6.12.79
B=/root/r36/linux-7.2.8

echo "=== MIPI-DSI related symbols, 6.12 vs 7.2 ==="
for K in "$A" "$B"; do
  echo "  --- $(basename "$K")"
  grep -iE "^CONFIG_(DRM_)?(MIPI_DSI|DW_MIPI_DSI|ROCKCHIP_DW_MIPI_DSI|DRM_DW_MIPI_DSI|DRM_PANEL_SIMPLE|DRM_ROCKCHIP)" "$K/.config" | sed 's/^/      /'
done
echo "  symbol names available in 7.2:"
grep -rhoE "^config (DRM_)?MIPI_DSI[A-Z_]*" "$B/drivers/gpu/drm/Kconfig" "$B/drivers/gpu/drm/bridge/Kconfig" 2>/dev/null | sort -u | sed 's/^/      /'

echo "=== does 7.2 still have of_gpio.h? ==="
ls -l "$B/include/linux/of_gpio.h" 2>&1 | sed 's/^/  /'
grep -rn "of_get_named_gpio\b" "$B/include/linux/gpio.h" "$B/include/linux/of.h" 2>/dev/null | head -4 | sed 's/^/  /'

echo "=== joypad driver: what does it actually call? ==="
J=/root/r36/k72test/joypad
grep -nE "of_get_named_gpio|of_gpio|gpio_[a-z_]+\(|devm_gpio|gpio_request" "$J/rocknix-joypad.c" | head -20
echo "  lines that would break without the legacy header:"
grep -c "of_get_named_gpio_flags" "$J/rocknix-joypad.c" | sed 's/^/    of_get_named_gpio_flags uses: /'

echo "=== the header the patch would create (from the .patch itself) ==="
awk '/^\+\+\+ b\/include\/linux\/of_gpio_legacy.h/{f=1;next} /^\+\+\+ b\//{f=0} f&&/^\+/{print substr($0,2)}' \
  /mnt/e/ubuntu/build/rocknix/patches-mainline/0001-gpiolib-of-revert-api-changes-needed-for-joypad-driv.patch | head -40
echo "=== diag2 done ==="
