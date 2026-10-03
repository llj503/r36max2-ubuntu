#!/bin/bash
# k72-evcap.sh - open an event window on the joypad node and the adc-keys node.
#
# evtest 1.36 has NO --raw option: every earlier capture wrote a usage message
# instead of events, which is why "12 lines and no events" kept happening.  The
# normal output line is
#   Event: time 1790988082.318388, type 1 (EV_KEY), code 304 (BTN_EAST), value 1
# note the comma before "value" - the old regexes had ") value" and matched
# nothing even when events were present.  Both bugs are fixed here.
#
# Usage:  bash k72-evcap.sh [seconds]     (default 300)
# Read it later with: bash k72-evread.sh  (window can still be open)
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
DUR=${1:-300}
JOY=/dev/input/by-path/platform-rocknix-singleadc-joypad-event-joystick
ADC=/dev/input/by-path/platform-adc-keys-event
sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV "pkill -x evtest 2>/dev/null; sleep 1
  rm -f /tmp/evjoy.txt /tmp/evadc.txt
  ( timeout $DUR evtest $JOY > /tmp/evjoy.txt 2>&1 & )
  ( timeout $DUR evtest $ADC > /tmp/evadc.txt 2>&1 & )
  echo \"  window: ${DUR}s on \$(( \$(date +%s) )) \$(date +%H:%M:%S)\"
  echo \"  module on card: \$(sha256sum /lib/modules/\$(uname -r)/extra/rocknix-singleadc-joypad.ko | cut -c1-16)\"
  echo \"  loaded: \$(lsmod | awk '/joypad/{print \$1\"=\"\$3\" used\"}' | tr '\n' ' ')\"
  mount -t debugfs none /sys/kernel/debug 2>/dev/null
  grep -iE 'rumble|amux' /sys/kernel/debug/gpio 2>/dev/null | sed 's/^/  pin: /'"
echo "=== capture window open for ${DUR}s ==="
