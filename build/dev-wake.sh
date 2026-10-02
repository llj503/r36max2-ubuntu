#!/bin/bash
# dev-wake.sh - make the power key able to wake the machine, with an RTC alarm as
# a safety net so a failed wake cannot leave the device bricked.
set -uo pipefail
DEV=192.168.31.210
PW=ubuntu
S() { sshpass -p "$PW" ssh -o ConnectTimeout=10 root@$DEV "$@" </dev/null 2>/dev/null; }

echo "=== 1. find the pwrkey / pmic devices ==="
S 'PK=$(find /sys/devices -maxdepth 7 -type d \( -name "rk805*pwrkey*" -o -name "*pwrkey*" \) | head -1)
   PM=$(find /sys/devices -maxdepth 7 -type d -name "0-0020" | head -1)
   echo "  pwrkey: $PK"; echo "  pmic  : $PM"
   echo "  pwrkey wakeup: $(cat $PK/power/wakeup 2>/dev/null)"
   echo "  pmic   wakeup: $(cat $PM/power/wakeup 2>/dev/null)"
   echo "  mem_sleep: $(cat /sys/power/mem_sleep)"'

echo "=== 2. allow wakeup on pwrkey + pmic + rtc (+ the gpio irq parent) ==="
S 'PK=$(find /sys/devices -maxdepth 7 -type d \( -name "rk805*pwrkey*" -o -name "*pwrkey*" \) | head -1)
   PM=$(find /sys/devices -maxdepth 7 -type d -name "0-0020" | head -1)
   RC=$(find /sys/devices -maxdepth 8 -type d -name "*rtc*" | head -3)
   for d in "$PK" "$PM" "$(dirname "$PM")" $RC; do
     [ -n "$d" ] || continue
     echo enabled > "$d/power/wakeup" 2>/dev/null && echo "  enabled: $d -> $(cat $d/power/wakeup)"
   done
   grep -H . /sys/kernel/debug/gpio | grep -iE "pmic|rk817" | head -3'

echo "=== 3. RTC alarm: wake in 45s no matter what ==="
S 'date -u; echo 0 > /sys/class/rtc/rtc0/wakealarm 2>/dev/null
   echo "+45" > /sys/class/rtc/rtc0/wakealarm && echo "  armed: $(cat /sys/class/rtc/rtc0/wakealarm) epoch"
   echo -n "  suspend_stats before: "; cat /sys/power/suspend_stats/success'

echo "=== 4. s2idle suspend (detached so this session can return) ==="
S 'echo s2idle > /sys/power/mem_sleep; echo "  mem_sleep now: $(cat /sys/power/mem_sleep)"
   systemd-run --quiet --collect /bin/sh -c "sleep 3; echo mem > /sys/power/state" && echo "  suspending in 3s"'

T0=$(date +%s); UP=no
for i in $(seq 1 40); do
  sleep 3
  if S 'echo ok' >/dev/null 2>&1; then UP=yes; echo "  ssh back after $(( $(date +%s) - T0 ))s"; break; fi
done
[ "$UP" = no ] && echo "  !!! still unreachable after 120s - 等 RTC 唤醒或按电源键"

echo "=== 5. did it sleep and wake? ==="
S 'echo -n "  suspend success count: "; cat /sys/power/suspend_stats/success
   echo -n "  failed_suspend: "; cat /sys/power/suspend_stats/failed_suspend
   echo -n "  failed_resume : "; cat /sys/power/suspend_stats/failed_resume
   echo "  last 12 PM lines:"; journalctl -b --no-pager -o short-iso 2>/dev/null | grep -iE "PM:|suspend|resum|wake" | tail -12 | sed "s/^/    /"
   echo -n "  now: "; date; echo -n "  boot: "; uptime -s
   echo 0 > /sys/class/rtc/rtc0/wakealarm 2>/dev/null; echo "  alarm cleared"'
