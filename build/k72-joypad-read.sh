#!/bin/bash
# k72-joypad-read.sh - read the joypad driver's GPIO usage and the DT binding it
# expects, so the gpiod conversion is written against the real thing.
set -uo pipefail
J=/root/r36/joypad/src
DTS=/root/r36/linux-6.12.79/arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dts

echo "=== files ==="
ls -l "$J"/*.c "$J"/*.h 2>/dev/null | awk '{print "  ", $5, $9}'

echo "=== includes ==="
grep -n "^#include" "$J/rocknix-joypad.c" | sed 's/^/  /'

echo "=== the struct holding button state ==="
awk '/^struct [a-z_]*gpio[a-z_]* \{/,/^\};/' "$J/rocknix-joypad.c" "$J/rocknix-joypad.h" 2>/dev/null | sed 's/^/  /'
grep -n -A14 "struct joypad {" "$J/rocknix-joypad.c" "$J/rocknix-joypad.h" 2>/dev/null | head -34 | sed 's/^/  /'

echo "=== every legacy GPIO call ==="
grep -nE "gpio_get_value|gpio_set_value|gpio_is_valid|gpio_request|of_get_gpio|of_get_named_gpio|GPIO_[A-Z]+|devm_gpio" "$J/rocknix-joypad.c" | sed 's/^/  /'

echo "=== joypad_gpio_setup() in full ==="
awk '/^static int joypad_gpio_setup/,/^}/' "$J/rocknix-joypad.c" | sed 's/^/  /'

echo "=== the poll function ==="
awk '/^static void joypad_gpio_check/,/^}/' "$J/rocknix-joypad.c" | sed 's/^/  /'

echo "=== rumble setup + use ==="
grep -n -B3 -A8 "rumble_gpio" "$J/rocknix-joypad.c" | head -60 | sed 's/^/  /'

echo "=== the DT node the driver binds to ==="
awk '/joypad: |retrogame|singleadc|joypad \{/,/^\t\t\};/' "$DTS" | head -60 | sed 's/^/  /'
grep -n "rocknix,singleadc-joypad\|rocknix-singleadc-joypad\|joypad" "$DTS" | head -10 | sed 's/^/  /'
echo "=== read done ==="
