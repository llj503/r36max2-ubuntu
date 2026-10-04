#!/bin/bash
# kill-midflip.sh - push the flip probe + the kill-mid-flip experiment to the
# card, build the probe there (libdrm-dev is in the image), and run it.
#
# READ THIS BEFORE RUNNING: phase [1] tries to reproduce the panel freeze on
# purpose.  If it succeeds the DSI pipeline stays wedged and only a reboot clears
# it - the script stops at the first success and says so loudly.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
SRC=/mnt/e/ubuntu/build

echo "=== push sources ==="
sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV 'mkdir -p /usr/local/src /usr/local/bin'
sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV 'cat > /usr/local/src/r36-flipprobe.c' < "$SRC/r36-flipprobe.c"
sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV 'cat > /usr/local/bin/r36-killmidflip.sh' < "$SRC/r36-killmidflip-device.sh"

echo "=== build the probe on the device ==="
timeout 120 sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV \
  'chmod 755 /usr/local/bin/r36-killmidflip.sh
   cc -O2 -Wall -o /usr/local/bin/r36-flipprobe /usr/local/src/r36-flipprobe.c $(pkg-config --cflags --libs libdrm) 2>&1 | head -20
   echo "  cc exit=$?"
   ls -l /usr/local/bin/r36-flipprobe 2>/dev/null | sed "s/^/  /"
   /usr/local/bin/r36-flipprobe 2 5 2>&1 | head -6 | sed "s/^/  smoke: /"
   echo "  smoke rc=$?"' 2>&1 | tail -14

echo
echo "=== run the experiment ==="
timeout 900 sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV 'sh /usr/local/bin/r36-killmidflip.sh' 2>&1
rc=$?
echo "=== experiment rc=$rc  (1 = reproduced the stall, 0 = not reproduced, 4 = card already stalled) ==="
[ "$rc" = 1 ] && echo "    the panel is likely frozen now: ask before rebooting"
