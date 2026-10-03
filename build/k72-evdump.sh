#!/bin/bash
# k72-evdump.sh - what is actually in the capture files?  The parser assumed
# evtest's normal format; --raw may print something else entirely, in which case
# "0 events" was my regex, not the hardware.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV 'echo "  uptime: $(cut -d" " -f1 /proc/uptime)s   date: $(date "+%m-%d %H:%M:%S")"
   for f in /tmp/evjoy.txt /tmp/evadc.txt; do
     echo "=== $f ($(wc -l < $f 2>/dev/null || echo missing) lines) ==="
     head -14 "$f" 2>/dev/null | cat -A | sed "s/^/    /" | cut -c1-160
   done
   echo "=== evtest version and what --raw emits (5s on the joypad node) ==="
   evtest --version 2>&1 | head -2 | sed "s/^/    /"
   timeout 5 evtest --raw /dev/input/by-path/platform-rocknix-singleadc-joypad-event-joystick 2>&1 | head -12 | sed "s/^/    /"
   echo "=== normal mode for comparison (3s) ==="
   timeout 3 evtest /dev/input/by-path/platform-rocknix-singleadc-joypad-event-joystick 2>&1 | tail -6 | sed "s/^/    /"'
echo "=== done ==="
