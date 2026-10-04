#!/bin/bash
# dev-keys.sh - make sure evtest/jstest exist, then record every input event for
# 4 minutes in the background so the user can press buttons at their own pace.
set -uo pipefail
DEV=root@192.168.31.210
PW=ubuntu
S() { sshpass -p "$PW" ssh "$DEV" "$@"; }

echo "=== install evtest / input-utils if apt is free ==="
S 'if pgrep -x apt-get >/dev/null; then echo "apt busy, using what is there"; else
     DEBIAN_FRONTEND=noninteractive apt-get -y -qq install evtest input-utils >/dev/null 2>&1 && echo "installed evtest+input-utils";
   fi
   command -v evtest jstest || true'

echo "=== devices to watch ==="
S 'ls -l /dev/input/by-path/; grep -E "^N|^H" /proc/bus/input/devices'

echo "=== start a 240s capture of every event device ==="
S 'rm -f /tmp/keys.log
   ( for d in /dev/input/event*; do
       timeout 240 evtest --raw "$d" 2>/dev/null | sed "s#^#$(basename $d) #" >> /tmp/keys.log &
     done
     wait ) >/dev/null 2>&1 &'
S 'sleep 2; pgrep -c evtest; wc -l /tmp/keys.log 2>/dev/null'

echo "=== also snapshot the joystick axes with jstest for 3s (no press needed) ==="
S 'command -v jstest >/dev/null && timeout 3 jstest /dev/input/js0 2>/dev/null | head -20 || echo "jstest not available yet"'
