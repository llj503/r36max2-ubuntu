#!/bin/bash
# k72-btn-semantics-audit.sh - pin down, for every GPIO the joypad driver uses,
# what physical level the VERIFIED legacy driver drove/read versus what the
# gpiod conversion will drive/read with the current DT polarity flags.
set -uo pipefail
OLD=/root/r36/joypad/src/rocknix-singleadc-joypad.c
NEW=/root/r36/k72joypad/rocknix-singleadc-joypad.c
DTS=/mnt/e/ubuntu/projects/r36max2/dt/rk3326-xifan-r36max2.dts
H7=/root/r36/linux-7.2.8/include/linux/gpio/consumer.h

echo "=== 1. the joypad node in our DT: which lines the driver owns ==="
awk '/rocknix-singleadc-joypad|singleadc/{f=1} f{print NR": "$0} f&&/^\t\};/{exit}' "$DTS" | head -70

echo
echo "=== 2. legacy poll loop: raw read + how the value becomes a key event ==="
sed -n '610,700p' "$OLD"

echo
echo "=== 3. converted poll loop: same region ==="
sed -n '400,500p' "$NEW"

echo
echo "=== 4. how the conversion acquires the button descs ==="
sed -n '800,840p' "$NEW"
echo "--- legacy equivalent ---"
sed -n '790,860p' "$OLD" | grep -nE "of_get_named_gpio|gpio_request|devm_gpio" | head -10

echo
echo "=== 5. raw vs logical API available in 7.2.8 ==="
grep -nE "gpiod_(set|get)_raw_value|GPIOD_OUT_(LOW|HIGH)_RAW|gpiod_direction_output_raw|gpiod_set_raw_value_cansleep|gpiod_get_raw_value_cansleep|GPIOD_AS_IS" "$H7" | head -20
