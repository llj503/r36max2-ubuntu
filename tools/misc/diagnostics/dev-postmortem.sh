#!/bin/bash
# dev-postmortem.sh - was the black screen a real suspend (and no wake source) or
# a crash? read the PREVIOUS boot's journal, then make the power key harmless
# until the wake path is proven.
set -uo pipefail
DEV=192.168.31.210
PW=ubuntu
S() { sshpass -p "$PW" ssh -o ConnectTimeout=10 root@$DEV "$@" </dev/null 2>/dev/null; }

echo "=== reachable? ==="
S 'echo ONLINE; uptime -s; who -b 2>/dev/null | tail -1'

echo "=== previous boot: last 30 lines ==="
S 'journalctl -b -1 --no-pager -o short-iso 2>/dev/null | tail -30'

echo "=== previous boot: power management lines ==="
S 'journalctl -b -1 --no-pager 2>/dev/null | grep -iE "PM:|suspend|resum|freez|wake" | tail -20'

echo "=== previous boot: oops / panic / errors ==="
S 'journalctl -b -1 -p 3 --no-pager 2>/dev/null | tail -20'

echo "=== this boot: suspend stats (should be 0 if the old boot never finished a cycle) ==="
S 'for f in success failed_suspend failed_resume last_errno; do printf "  %-18s %s\n" "$f" "$(cat /sys/power/suspend_stats/$f 2>/dev/null)"; done'

echo "=== SAFETY: power key must not sleep the device until wake is proven ==="
S 'mkdir -p /etc/systemd/logind.conf.d
   sed -i "s/^HandlePowerKey=.*/HandlePowerKey=ignore/" /etc/systemd/logind.conf.d/99-r36-power.conf
   grep -E "HandlePowerKey" /etc/systemd/logind.conf.d/99-r36-power.conf
   systemctl restart systemd-logind && echo "  logind restarted"'

echo "=== where is the pwrkey, and is it allowed to wake anything? ==="
S 'PK=$(find /sys/devices -maxdepth 6 -type d -name "rk805_pwrkey*" | head -1); echo "  path: $PK"
   [ -n "$PK" ] && { echo "  wakeup currently: $(cat $PK/power/wakeup)"; }
   echo "  i2c parent wakeup: $(cat $(dirname $(dirname $PK))/power/wakeup 2>/dev/null)"
   echo "  pmic irq/wakeup:"; grep -riE "rk808|rk817" /proc/interrupts | head -3
   echo "  wakeup_sources with a real count:"; awk "NR==1 || \$5+0>0" /sys/kernel/debug/wakeup_sources 2>/dev/null | head -8'
