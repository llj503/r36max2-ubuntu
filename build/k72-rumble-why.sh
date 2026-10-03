#!/bin/bash
# k72-rumble-why.sh - the line is de-asserted now (module unloaded). Find out
# what called vibrator_start in the first place: the input-open path or a real
# force-feedback effect.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
F=/root/r36/k72joypad/rocknix-singleadc-joypad.c

echo "=== call sites of the vibrator in the driver ==="
grep -n "joypad_vibrator_start\|joypad_vibrator_stop\|rumble_play_effect\|input_set_capability.*FF\|ff_effects_max\|EV_FF\|input_register_device\|joypad_open\|joypad_close\|->open\|flush" "$F" | head -25 | sed 's/^/  /'

echo "=== the function that opens the input device ==="
awk '/static int joypad_open/,/^}/' "$F" | head -30 | sed 's/^/  /'

echo "=== rumble_play_effect + its registration ==="
awk '/static int rumble_play_effect/,/^}/' "$F" | head -25 | sed 's/^/  /'
grep -n "input_ff_create\|ff_effects" "$F" | sed 's/^/  /'

echo "=== current line state on the device ==="
sshpass -p $PW ssh -o ConnectTimeout=15 root@$DEV \
  'mount -t debugfs none /sys/kernel/debug 2>/dev/null; \
   cat /sys/kernel/debug/gpio | grep -iE "rumble|amux" | sed "s/^/  /"; \
   echo "  joypad loaded: $(lsmod | grep -c joypad)"' </dev/null 2>/dev/null
