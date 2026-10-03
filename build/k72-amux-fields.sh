#!/bin/bash
# k72-amux-fields.sh - where are sel_a_gpio / sel_b_gpio / en_gpio declared?
set -uo pipefail
echo "=== declarations in the pristine tree ==="
grep -rn "sel_a_gpio\|sel_b_gpio\|en_gpio" /root/r36/joypad/src/*.h /root/r36/joypad/src/rocknix-singleadc-joypad.c | grep -E "int|struct|\[" | head -12 | sed 's/^/  /'
echo "=== struct analog_mux definition ==="
awk '/struct analog_mux \{/,/\};/' /root/r36/joypad/src/rocknix-joypad.h /root/r36/joypad/src/rocknix-singleadc-joypad.c 2>/dev/null | sed 's/^/  /'
echo "=== same, in the converted tree ==="
awk '/struct analog_mux \{/,/\};/' /root/r36/k72joypad/rocknix-joypad.h /root/r36/k72joypad/rocknix-singleadc-joypad.c 2>/dev/null | sed 's/^/  /'
