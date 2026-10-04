#!/bin/bash
# k72-joypad-capture.sh - record input events for 45 seconds while the user
# presses everything, then summarise which codes actually arrived.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
EV=/dev/input/by-path/platform-rocknix-singleadc-joypad-event-joystick
S() { sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV "$@" </dev/null 2>/dev/null; }

echo "capturing 45s from $EV  (device kernel $(S 'uname -r'))"
S "rm -f /tmp/ev.txt /tmp/js.txt
   ( timeout 45 evtest --raw $EV > /tmp/ev.txt 2>&1 & )
   ( timeout 40 sh -c 'while :; do jstest /dev/input/js0 2>/dev/null | head -40; sleep 0.4; done > /tmp/js.txt 2>&1' & )
   sleep 2; echo '  capture running'"
sleep 46
S 'echo "=== evtest lines: $(wc -l < /tmp/ev.txt) ==="
   grep -oE "type 1 \(EV_KEY\), code [0-9]+ \([A-Z_0-9]+\)" /tmp/ev.txt | sort -u | sed "s/^/  key: /"
   grep -oE "type 3 \(EV_ABS\), code [0-9]+ \([A-Z_0-9]+\)" /tmp/ev.txt | sort -u | sed "s/^/  abs: /"
   echo "=== value changes seen (first 25 events) ==="
   grep -E "^Event: time" -A1 /tmp/ev.txt | grep -E "value" | head -25 | sed "s/^/  /"
   echo "=== joystick axis extremes from jstest ==="
   grep -oE "^\s+[0-9]+: *value +[0-9-]+" /tmp/js.txt | sort -u -k4 -n | head -20 | sed "s/^/  /"
   echo "=== errors? ==="
   dmesg | tail -5 | sed "s/^/  /"'
echo "=== capture done ==="
