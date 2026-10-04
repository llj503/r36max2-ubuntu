#!/bin/bash
# k72-btnsetup-callsite.sh - the 17 button descriptors are clearly never claimed
# (nothing in /sys/kernel/debug/gpio), so find out whether the setup function is
# even called, and compare with the legacy call order.
set -uo pipefail
NEW=/root/r36/k72joypad/rocknix-singleadc-joypad.c
OLD=/root/r36/joypad/src/rocknix-singleadc-joypad.c

echo "=== which function contains the button desc loop (NEW) ==="
awk '/^[a-zA-Z_].*\(.*\)$/{fn=$0} /devm_fwnode_gpiod_get_index/{print NR": in "fn; exit}' "$NEW"
grep -n "^static int\|^static void\|^int \|^void " "$NEW" | sed -n '1,60p' | awk -F: '{print $1": "$2}' | grep -iE "gpio|setup|parse|probe" | sed 's/^/  /'

echo
echo "=== every call site of the button setup, NEW vs OLD ==="
echo "--- NEW:"
grep -n -E "joypad_gpio_setup|gpio_setup|joypad_dt_parse|joypad_input_setup|joypad_probe" "$NEW" | sed 's/^/    /'
echo "--- OLD:"
grep -n -E "joypad_gpio_setup|gpio_setup|joypad_dt_parse|joypad_input_setup|joypad_probe" "$OLD" | sed 's/^/    /'

echo
echo "=== the probe body, side by side (NEW) ==="
sed -n "$(grep -n 'static int joypad_probe' "$NEW" | cut -d: -f1),+70p" "$NEW"
echo
echo "=== the probe body (OLD) ==="
sed -n "$(grep -n 'static int joypad_probe' "$OLD" | cut -d: -f1),+70p" "$OLD"
