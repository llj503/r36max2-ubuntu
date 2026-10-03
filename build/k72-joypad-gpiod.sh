#!/bin/bash
# k72-joypad-gpiod.sh - confirm the gpiod helpers exist in both kernel trees, and
# show the button child nodes (property names) the driver parses.
set -uo pipefail
DTS=/root/r36/linux-6.12.79/arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dts

for K in /root/r36/linux-6.12.79 /root/r36/linux-7.2.8; do
  echo "--- $(basename "$K")"
  H="$K/include/linux/gpio/consumer.h"
  for fn in devm_fwnode_gpiod_get_index devm_gpiod_get_index_optional \
            devm_gpiod_get_optional gpiod_get_value_cansleep gpiod_set_value_cansleep; do
    if grep -q "$fn" "$H" 2>/dev/null; then echo "  present  $fn"; else echo "  MISSING  $fn"; fi
  done
  echo "  exported by gpiolib:"
  grep -oE "EXPORT_SYMBOL(_GPL)?\((devm_fwnode_gpiod_get_index|devm_gpiod_get_index|gpiod_get_raw_value_cansleep|gpiod_set_value_cansleep)\)" \
      "$K/drivers/gpio/gpiolib.c" "$K/drivers/gpio/gpiolib-devres.c" "$K/drivers/gpio/gpiolib-of.c" 2>/dev/null | sed 's/.*EXPORT/    EXPORT/' | sort -u
done

echo "=== button child nodes in the joypad DT node ==="
awk '/joypad: rocknix-singleadc-joypad/,/^\t};/' "$DTS" | grep -nE "button|gpio|linux,code|label|amux|adc|vibrator|rumble" | head -40 | sed 's/^/  /'

echo "=== a full sample child node ==="
awk '/joypad: rocknix-singleadc-joypad/,/^\t};/' "$DTS" | sed -n '/btn_up\|button-0\|key_up\|btn-a\|button@0/,/};/p' | head -18 | sed 's/^/  /'

echo "=== how many gpio buttons does the driver expect (bt_gpio_count)? ==="
grep -n "bt_gpio_count" /root/r36/joypad/src/rocknix-joypad.c | head -6 | sed 's/^/  /'
