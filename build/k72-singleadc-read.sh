#!/bin/bash
# k72-singleadc-read.sh - the module the board actually binds to is
# rocknix-singleadc-joypad, not rocknix-joypad.  Show its legacy GPIO usage so
# the same conversion can be applied to it.
set -uo pipefail
F=/root/r36/joypad/src/rocknix-singleadc-joypad.c
echo "=== includes ==="
grep -n "^#include" "$F" | sed 's/^/  /'
echo "=== legacy GPIO references ==="
grep -nE "gpio_is_valid|gpio_get_value|gpio_set_value|of_get_gpio|of_get_named_gpio|devm_gpio_request|OF_GPIO_|gpio_direction|struct gpio_desc|gpiod_|->num|gpio_desc" "$F" | sed 's/^/  /'
echo "=== count ==="
grep -cE "gpio_is_valid|gpio_get_value|gpio_set_value|of_get_gpio|of_get_named_gpio|devm_gpio_request" "$F" | sed 's/^/  legacy sites: /'
grep -c "gpiod_" "$F" | sed 's/^/  already-gpiod uses: /'
echo "=== struct with num ==="
sed -n '/^struct bt_gpio {/,/^};/p' "$F" | sed 's/^/  /'
echo "=== which module does the DT bind? ==="
grep -n "compatible" "$F" | head -5 | sed 's/^/  /'
grep -n "MODULE_DEVICE_TABLE\|\.name =" "$F" | head -5 | sed 's/^/  /'
