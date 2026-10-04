#!/bin/bash
# dev-suspend2.sh - actually suspend it (detached, so ssh can return), make sure
# the power key can wake it, then watch for it to come back.
set -uo pipefail
DEV=192.168.31.210
PW=ubuntu
S() { sshpass -p "$PW" ssh -o ConnectTimeout=8 root@$DEV "$@" </dev/null 2>/dev/null; }

echo "=== logind drop-in in place? ==="
S 'grep -rH . /etc/systemd/logind.conf.d/ 2>/dev/null | sed "s/^/  /"'

echo "=== locate the pwrkey device and enable wakeup on it ==="
S 'PK=$(find /sys/devices -maxdepth 5 -type d -name "rk805_pwrkey*" | head -1); echo "  pwrkey dev: $PK"
   [ -n "$PK" ] && { echo enable > "$PK/power/wakeup"; echo "  wakeup now: $(cat $PK/power/wakeup)"; }
   echo "  wakeup_sources (top):"; grep -v "^enabled[[:space:]]" /sys/kernel/debug/wakeup_sources 2>/dev/null | head -6'

echo "=== suspend stats before ==="
S 'for f in success failed_suspend failed_prepare failed_suspend_late failed_resume; do printf "  %-20s %s\n" "$f" "$(cat /sys/power/suspend_stats/$f 2>/dev/null)"; done'

echo "=== arm the sleep 4s from now (detached), then I poll for its return ==="
S 'systemd-run --quiet --collect --description="r36 test suspend" /bin/sh -c "sleep 4; echo mem > /sys/power/state" && echo "  armed"'
sleep 12
T0=$(date +%s)
for i in $(seq 1 100); do
  if ping -n -c1 -W1 $DEV >/dev/null 2>&1; then
    echo "  back online after $(( $(date +%s) - T0 ))s of polling"
    break
  fi
  sleep 2
done
[ $i -eq 100 ] && echo "  STILL DOWN after 200s - 长按电源键 3 秒强制开机"

echo "=== suspend stats after ==="
S 'for f in success failed_suspend failed_prepare failed_suspend_late failed_resume; do printf "  %-20s %s\n" "$f" "$(cat /sys/power/suspend_stats/$f 2>/dev/null)"; done'
echo "=== kernel log of the cycle ==="
S 'journalctl -b --no-pager -o short-monotonic 2>/dev/null | grep -iE "suspend|resume|wake|freez|PM: " | tail -22'
echo "=== did wifi survive? ==="
S 'ip -br addr show wlan0; iw dev wlan0 link | head -2'
