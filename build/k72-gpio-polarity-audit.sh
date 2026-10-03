#!/bin/bash
# k72-gpio-polarity-audit.sh - the gpiod conversion replaced raw gpio_set_value()
# with polarity-aware gpiod_set_value().  Any DT line marked GPIO_ACTIVE_LOW then
# drives the OPPOSITE physical level it used to, which would silently break the
# ADC mux (wrong channel -> wrong keys / swapped sticks) even though the module
# loads.  Compare old vs new write/read sites against the DT flags.
set -uo pipefail
OLD=/root/r36/joypad/src/rocknix-singleadc-joypad.c
NEW=/root/r36/k72joypad/rocknix-singleadc-joypad.c
DTS=/mnt/e/ubuntu/board/rk3326-xifan-r36max2.dts

echo "=== DT gpio flags the driver inherits ==="
grep -nE "amux-[abs]-gpios|amux-en-gpios|rumble-gpio|gpio-keys|gpios = <&gpio" "$DTS" | head -30

echo
echo "=== ORIGINAL: how the mux and buttons were driven ==="
sed -n '300,360p' "$OLD"
echo "--- original button scan (raw reads) ---"
grep -nE "gpio_get_value|gpio_set_value|input_report_key|->value|state" "$OLD" | head -25

echo
echo "=== CONVERTED: same regions ==="
sed -n '300,360p' "$NEW"
echo "--- converted button scan (gpiod reads) ---"
grep -nE "gpiod_get_value|gpiod_set_value|gpiod_set_raw|input_report_key|->value|state" "$NEW" | head -25

echo
echo "=== how the gpiod conversion requested each desc (direction/flags) ==="
grep -nE "devm_gpiod_get|devm_fwnode_gpiod_get_index|gpiod_get_optional|GPIOD_IN|GPIOD_OUT" "$NEW" | head -20

echo
echo "=== the exact lines the poll loop compares against ==="
grep -n -B3 -A12 "gpiod_get_value_cansleep" "$NEW" | head -60
