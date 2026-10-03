#!/bin/bash
# k72-btn-opencap.sh - does the driver's open() report the 17 buttons at all?
# joypad_open() emits them unconditionally, so a short capture shows whether the
# button loop runs and what report_type/code it uses.  Also dump the two source
# regions that decide it.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
S() { sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV "$@" </dev/null 2>/dev/null; }

echo "=== 4s capture on event2, printed from the first line ==="
S 'rm -f /tmp/evopen.txt
   timeout 4 evtest /dev/input/by-path/platform-rocknix-singleadc-joypad-event-joystick > /tmp/evopen.txt 2>&1
   echo "  lines: $(wc -l < /tmp/evopen.txt)"
   head -32 /tmp/evopen.txt | sed "s/^/    /"
   echo "  --- event type histogram:"
   grep -oE "type [0-9]+ \([A-Z_]+\)" /tmp/evopen.txt | sort | uniq -c | sed "s/^/    /"
   echo "  --- any EV_KEY?  $(grep -c "EV_KEY" /tmp/evopen.txt)"
   echo "  --- dev_err during that open: $(dmesg | grep -ac "failed to get gpio state") total"'

echo
echo "=== the poll-side button loop as it now stands ==="
sed -n '615,650p' /root/r36/k72joypad/rocknix-singleadc-joypad.c

echo
echo "=== bt_gpio_count: where it is counted, where it is assigned ==="
grep -n "bt_gpio_count" /root/r36/k72joypad/rocknix-singleadc-joypad.c | sed "s/^/  /"
echo "--- the counting loop in dt_parse ---"
sed -n '1509,1575p' /root/r36/k72joypad/rocknix-singleadc-joypad.c
echo "=== opencap done ==="
