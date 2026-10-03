#!/bin/bash
# k72-new-driver-dump.sh - dump the exact GPIO write/read sites in the converted
# driver plus the legacy code they replaced, so the raw-vs-logical patch can be
# written without guessing.
set -uo pipefail
OLD=/root/r36/joypad/src/rocknix-singleadc-joypad.c
NEW=/root/r36/k72joypad/rocknix-singleadc-joypad.c
OLD2=/root/r36/joypad/src/rocknix-joypad.c
NEW2=/root/r36/k72joypad/rocknix-joypad.c

echo "########## SINGLE-ADC (the one this board uses) ##########"
echo "=== NEW: every gpiod call with 3 lines of context ==="
grep -n -B2 -A3 "gpiod_" "$NEW"

echo
echo "=== NEW: active_level / old_value / report_type usage ==="
grep -n "active_level\|old_value\|trigger\|OF_GPIO_ACTIVE_LOW\|of_get_gpio_flags\|GPIO_ACTIVE_LOW" "$NEW" | head -30

echo
echo "=== OLD: how active_level was computed (the polarity the legacy code did by hand) ==="
grep -n -B4 -A10 "active_level" "$OLD" | head -60

echo
echo "=== OLD: how the mux gpios were requested ==="
grep -n -B3 -A12 "amux-a-gpios\|amux_en\|amux-en-gpios\|gpio_request" "$OLD" | sed -n '1,80p'

echo
echo "=== NEW: how the mux gpios are requested now ==="
grep -n -B3 -A12 "amux\|devm_gpiod_get" "$NEW" | sed -n '1,80p'

echo
echo "########## PLAIN JOYPAD (unused on this board, but same conversion) ##########"
grep -n "gpiod_\|active_level" "$NEW2" | head -30
