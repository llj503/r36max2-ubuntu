#!/bin/bash
# k72-joypad-dump.sh - verbatim text of every region the gpiod rewrite touches,
# so the replacements match byte-for-byte instead of being guessed.
set -uo pipefail
F=/root/r36/joypad/src/rocknix-joypad.c
show() {  # $1 label, $2 from, $3 to
  echo "--- $1 ($2-$3)"
  awk -v a="$2" -v b="$3" 'NR>=a && NR<=b {printf "%4d| %s\n", NR, $0}' "$F" | cat -A | sed 's/\$$//' | sed 's/^/  /'
}
show "includes" 8 32
show "bt_gpio struct" 40 62
show "rumble on/off" 350 375
show "poll" 412 440
show "setup loop head" 800 828
show "setup loop tail" 828 870
show "probe rumble" 1005 1030
show "line 760ish" 758 775
echo "--- struct joypad fields"
awk 'NR>=82 && NR<=130 {printf "%4d| %s\n", NR, $0}' "$F" | sed 's/^/  /'
