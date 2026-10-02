#!/bin/bash
# Push the fixed status page to the device, restart it, and screenshot the result.
set -uo pipefail
DEV=root@192.168.31.210
PW=ubuntu
S() { sshpass -p "$PW" ssh "$DEV" "$@"; }

sshpass -p "$PW" scp -q /mnt/e/ubuntu/build/r36-status-screen "$DEV:/usr/local/sbin/r36-status-screen"
S "chmod 755 /usr/local/sbin/r36-status-screen; sh -n /usr/local/sbin/r36-status-screen && systemctl restart r36-status-screen && echo PUSHED-AND-RESTARTED"
S "grep -nE 'WLAN=|DRV=|SIG=|dev/tty1' /usr/local/sbin/r36-status-screen | head -6"
echo "=== boot time mystery ==="
S 'echo -n "uptime now: "; cat /proc/uptime; echo -n "boot: "; uptime -s; echo -n "wall: "; date -Is'
echo "=== apt ==="
S 'tail -2 /root/setup.log; pgrep -c apt-get 2>/dev/null || echo "apt-get done"; dpkg -l 2>/dev/null | awk "/^ii/{n++} END {print \"packages installed: \" n}"; command -v evtest jstest aplay speaker-test git gcc python3 2>/dev/null | tr "\n" " "'
sleep 3
bash /mnt/e/ubuntu/build/shot.sh 2>&1 | tail -3
