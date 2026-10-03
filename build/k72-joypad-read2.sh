#!/bin/bash
# k72-joypad-read2.sh - the rest of the picture: the button setup loop, the poll
# function, the DT node shape, and whether the gpiod helpers we plan to use
# exist in BOTH 6.12 and 7.2 (so one source works on both kernels).
set -uo pipefail
J=/root/r36/joypad/src
DTS=/root/r36/linux-6.12.79/arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dts

echo "=== joypad_gpio_setup: the loop ==="
sed -n '/^static int joypad_gpio_setup/,/^}/p' "$J/rocknix-joypad.c" | sed -n '20,70p' | sed 's/^/  /'

echo "=== joypad_gpio_check (poll) ==="
sed -n '/^static void joypad_gpio_check/,/^}/p' "$J/rocknix-joypad.c" | sed 's/^/  /'

echo "=== bt_gpio struct + rumble field ==="
sed -n '/^struct bt_gpio {/,/^};/p' "$J/rocknix-joypad.c" | sed 's/^/  /'
grep -n "rumble_gpio" "$J/rocknix-joypad.c" | head -8 | sed 's/^/  /'

echo "=== the joypad DT node ==="
awk '/joypad \{|joypad:/{f=1} f{print} f&&/^\t\};/{exit}' "$DTS" | head -70 | sed 's/^/  /'

echo "=== gpiod helpers available in each tree ==="
for K in /root/r36/linux-6.12.79 /root/r36/linux-7.2.8; do
  echo "  --- $(basename "$K")"
  for fn in devm_fwnode_gpiod_get_index devm_gpiod_get_index gpiod_get_value_cansleep gpiod_set_value_cansleep devm_gpiod_get_optional; do
    n=$(grep -rl "$fn" "$K/include/linux/gpio/consumer.h" 2>/dev/null | wc -l)
    printf '      %-32s %s\n' "$fn" "$([ "$n" = 1 ] && echo present || echo MISSING)"
  done
done
echo "=== does 7.2 still export them to modules? ==="
grep -oE "EXPORT_SYMBOL[_A-Z]*\(devm_fwnode_gpiod_get_index\)|EXPORT_SYMBOL[_A-Z]*\(devm_gpiod_get_index_optional\)" /root/r36/linux-7.2.8/drivers/gpio/gpiolib.c | head -4 | sed 's/^/  /'
grep -c "EXPORT_SYMBOL" /root/r36/linux-7.2.8/drivers/gpio/gpiolib.c | sed 's/^/  gpiolib.c EXPORT_SYMBOL count: /'
echo "=== read2 done ==="
