#!/bin/bash
# k72-wait-ssh.sh - just WAIT for the board to come back (no reboot issued), then
# report the facts that decide whether the next experiment is worth starting:
# which kernel booted, how fresh the boot is, and whether the display pipeline is
# clean (0 stall messages) or already wedged again.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
S() { sshpass -p $PW ssh -o ConnectTimeout=5 root@$DEV "$@" </dev/null 2>/dev/null; }

found=""
for i in $(seq 1 40); do
  sleep 5
  for ip in 192.168.31.209 192.168.31.210 192.168.31.208 192.168.31.211; do
    if sshpass -p $PW ssh -o ConnectTimeout=5 root@$ip 'true' >/dev/null 2>&1 </dev/null; then
      DEV=$ip; found=yes; break 2
    fi
  done
  printf '.'
done
echo
[ -n "$found" ] || { echo "!! no ssh on the usual addresses after 200s"; exit 1; }
echo "[$(date +%H:%M:%S)] ssh back on $DEV"
S 'echo "  host=$(hostname)  uptime=$(cut -d. -f1 /proc/uptime)s";
   echo "  kernel=$(uname -r)";
   echo "  stall messages since boot=$(journalctl -b -k --no-pager 2>/dev/null | grep -cE \"vblank wait timed out|wait_for_vblanks|flip_done timed out\")";
   echo "  weston=$(systemctl is-active weston) keymapper=$(systemctl is-active r36-keymapper)";
   echo "  failed units: $(systemctl --failed --no-legend --no-pager | wc -l)";
   echo "  mem available=$(awk "/MemAvailable/{print int(\$2/1024)\" MB\"}" /proc/meminfo)";
   echo "  joypad=$(ls /dev/input/by-path/*joypad* 2>/dev/null | wc -l) js=$(ls /dev/input/js0 2>/dev/null)";
   echo "  dsi=$(cat /sys/class/drm/card0-DSI-1/status 2>/dev/null) blank=$(cat /sys/class/graphics/fb0/blank 2>/dev/null)"'
echo "=== wait-ssh done (DEV=$DEV) ==="
