#!/bin/bash
# dev-suspend.sh - suspend the device from here, watch when it comes back, and
# report the sleep/resume accounting + anything that failed on the way.
set -uo pipefail
DEV=192.168.31.210
PW=ubuntu
S() { sshpass -p "$PW" ssh -o ConnectTimeout=6 root@$DEV "$@" </dev/null 2>/dev/null; }

echo "=== pre-flight: what can wake it? ==="
S 'cat /proc/acpi/wakeup 2>/dev/null | head -3; for d in /sys/class/power_supply/battery /sys/class/rtc/rtc0; do :; done
   echo -n "pwrkey wakeup: "; grep -H . /sys/devices/platform/*pwrkey*/power/wakeup 2>/dev/null || grep -RH wakeup /sys/bus/platform/devices/*/power/wakeup 2>/dev/null | head -3
   echo -n "suspend state: "; cat /sys/power/state
   echo -n "mem sleep mode: "; cat /sys/power/mem_sleep 2>/dev/null
   echo -n "logind: "; grep -h HandlePowerKey /run/systemd/logind.conf.d/* /etc/systemd/logind.conf 2>/dev/null | head -2'

echo "=== trigger suspend, then poll for it to return ==="
T0=$(date +%s)
nohup bash -c 'for i in $(seq 1 90); do if ping -n -c1 -W1 192.168.31.210 >/dev/null 2>&1; then echo "$(date +%T) back online after $((i*2))s"; exit 0; fi; sleep 2; done; echo "still down after 180s"' > /tmp/ping.log 2>&1 &
PINGPID=$!
sleep 1
S 'systemctl suspend &>/dev/null &'
echo "suspend requested at $(date +%T)"
wait $PINGPID
echo "elapsed: $(( $(date +%s) - T0 ))s"
cat /tmp/ping.log

echo "=== what the kernel logged about the cycle ==="
S 'journalctl -b --no-pager -o short-iso 2>/dev/null | grep -iE "suspend|resume|wake|pm suspend|freezing" | tail -18'
echo "=== sleep statistics / failures ==="
S 'cat /sys/kernel/debug/pm_graph_max_sleep_time 2>/dev/null; pm-is-supported 2>/dev/null; echo "wakeup count: $(cat /sys/power/suspend_stats/success 2>/dev/null) success / $(cat /sys/power/suspend_stats/failed_suspend 2>/dev/null) failed_suspend / last_errno=$(cat /sys/power/suspend_stats/last_errno 2>/dev/null)"; cat /sys/power/suspend_stats/failed_suspend_late 2>/dev/null'
echo "=== anything that refused to freeze ==="
S 'journalctl -b --no-pager 2>/dev/null | grep -iE "freezing of tasks|could not freeze|oom|error .*suspend" | tail -8; ls /sys/kernel/debug/suspend_stats 2>/dev/null && cat /sys/kernel/debug/suspend_stats/* 2>/dev/null | head -14'
