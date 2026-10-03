#!/bin/bash
# k72-wait-newboot.sh - wait for a genuinely NEW boot, not merely "ssh answers".
#
# On this board a reboot issued while the display pipeline is wedged can spend
# tens of minutes in shutdown; during that window ssh still answers and a plain
# connectivity check reports "back" while uptime is still the old, huge number.
# So the condition is: hostname is r36max2 AND uptime is small.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
MAXUPT=${MAXUPT:-900}
ROUNDS=${ROUNDS:-90}          # 90 * 20s = 30 min ceiling

for i in $(seq 1 "$ROUNDS"); do
  out=$(timeout 20 sshpass -p $PW ssh -o ConnectTimeout=8 root@$DEV \
        'echo "host=$(hostname) uptime=$(cut -d. -f1 /proc/uptime)s kernel=$(uname -r)"' 2>/dev/null)
  up=$(printf '%s' "$out" | sed -n 's/.*uptime=\([0-9]*\)s.*/\1/p')
  if printf '%s' "$out" | grep -q "host=r36max2" && [ -n "$up" ] && [ "$up" -lt "$MAXUPT" ]; then
    echo "[$(date +%H:%M:%S)] NEW BOOT confirmed after $((i*20))s of waiting"
    echo "  $out"
    timeout 60 sshpass -p $PW ssh -o ConnectTimeout=10 root@$DEV \
      'echo "  stall since boot=$(journalctl -b -k --no-pager 2>/dev/null | grep -cE "vblank wait timed out|wait_for_vblanks|flip_done timed out")";
       echo "  weston=$(systemctl is-active weston) keymapper=$(systemctl is-active r36-keymapper) failed_units=$(systemctl --failed --no-legend --no-pager | wc -l)";
       echo "  vop irq: $(grep vop /proc/interrupts | head -1 | sed "s/  */ /g")";
       echo "  dsi=$(cat /sys/class/drm/card0-DSI-1/status 2>/dev/null) blank=$(cat /sys/class/graphics/fb0/blank 2>/dev/null) mem=$(awk "/MemAvailable/{print int(\$2/1024)}" /proc/meminfo)MB"' 2>&1
    exit 0
  fi
  printf '.'
  sleep 20
done
echo
echo "!! no new boot within the window (last seen: $out)"
exit 1
