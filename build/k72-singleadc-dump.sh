#!/bin/bash
# k72-singleadc-dump.sh - verbatim text of the amux GPIO blocks, the amux struct,
# and the poll sites in rocknix-singleadc-joypad.c.
set -uo pipefail
F=/root/r36/joypad/src/rocknix-singleadc-joypad.c
echo "=== amux struct ==="
sed -n '/^struct amux {/,/^};/p' "$F" | cat -A | sed 's/\$$//' | sed 's/^/  /'
grep -n "struct amux\b" "$F" | head -5 | sed 's/^/  ref: /'
echo "=== amux gpio setup (845-900) ==="
awk 'NR>=845 && NR<=900 {printf "%4d|%s\n", NR, $0}' "$F" | cat -A | sed 's/\$$//' | sed 's/^/  /'
echo "=== amux switching code (310-345) ==="
awk 'NR>=310 && NR<=345 {printf "%4d|%s\n", NR, $0}' "$F" | sed 's/^/  /'
echo "=== poll sites (620-640, 765-775) ==="
awk 'NR>=620 && NR<=640 {printf "%4d|%s\n", NR, $0}' "$F" | sed 's/^/  /'
awk 'NR>=765 && NR<=778 {printf "%4d|%s\n", NR, $0}' "$F" | sed 's/^/  /'
echo "=== rumble sites (1090-1100, 1590-1615) ==="
awk 'NR>=1090 && NR<=1100 {printf "%4d|%s\n", NR, $0}' "$F" | sed 's/^/  /'
awk 'NR>=1590 && NR<=1615 {printf "%4d|%s\n", NR, $0}' "$F" | sed 's/^/  /'
echo "=== struct joypad gpio fields ==="
grep -nE "int (rumble_gpio|bt_gpio_count)|struct amux \*|} amux" "$F" | head -8 | sed 's/^/  /'
