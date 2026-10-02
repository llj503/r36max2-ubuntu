#!/bin/bash
# k72-diag.sh - why does DRM_PANEL_GENERIC_DSI not appear in .config, and what
# exactly does the joypad driver need from the conflicting gpiolib patch?
set -uo pipefail
K=/root/r36/linux-7.2.8
cd "$K" || exit 1

echo "=== panel Kconfig dependencies ==="
grep -E "^(CONFIG_OF|CONFIG_MIPI_DSI|CONFIG_DRM|CONFIG_DRM_PANEL)=" .config | sort
echo "  file structure: menu=$(grep -c '^menu ' drivers/gpu/drm/panel/Kconfig) if=$(grep -cE '^if ' drivers/gpu/drm/panel/Kconfig) end=$(grep -c '^end' drivers/gpu/drm/panel/Kconfig) lines=$(wc -l < drivers/gpu/drm/panel/Kconfig)"
echo "  last 6 lines:"; tail -6 drivers/gpu/drm/panel/Kconfig | sed 's/^/    /'
echo "  how is it sourced?"; grep -rn "panel/Kconfig" drivers/gpu/drm/Kconfig | sed 's/^/    /'
echo "  scripts/config state:"; ./scripts/config --state DRM_PANEL_GENERIC_DSI 2>&1 | sed 's/^/    /'
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig 2>&1 | grep -viE "^  (HOSTCC|HOSTLD|GEN|CALL)" | tail -8

echo "=== what the gpiolib-revert patch actually adds ==="
P=/mnt/e/ubuntu/build/rocknix/patches-mainline/0001-gpiolib-of-revert-api-changes-needed-for-joypad-driv.patch
echo "  files touched:"; grep -E "^(\+\+\+|---) " "$P" | sort -u | head -12
echo "  symbols it introduces:"; grep -E "^\+.*(of_get_named_gpio_flags|of_gpio_named_count|EXPORT_SYMBOL|struct of_gpio_desc|of_gpio_flags)" "$P" | head -10
echo "  why it conflicts on 7.2:"; patch -p1 --dry-run -s -i "$P" 2>&1 | head -8

echo "=== what the joypad driver uses ==="
J=/root/r36/k72test/joypad
grep -n "#include" "$J/rocknix-joypad.c" | head -14
echo "  legacy-ish calls in the driver:"
grep -nE "of_get_named_gpio[_a-z]*|gpio_request|devm_gpio_request|gpio_to_desc|gpiod_get|of_gpio" "$J/rocknix-joypad.c" | head -12
echo "=== diag done ==="
