#!/bin/bash
# k72-up-check.sh - one SSH sweep over the usual addresses, printing the board's
# own identity.  Deliberately a FILE: inline `wsl.exe -- bash -c "...$(hostname)..."`
# gets expanded by the outer quoting layer and prints WSL's hostname while
# *pretending* to be the handheld (it happened twice today; both times I believed
# it and drew a wrong conclusion).
set -uo pipefail
PW=ubuntu
for ip in 192.168.31.209 192.168.31.210 192.168.31.208 192.168.31.211 192.168.31.1; do
  out=$(timeout 15 sshpass -p $PW ssh -o ConnectTimeout=8 -o StrictHostKeyChecking=no root@$ip \
        'echo "host=$(hostname) kernel=$(uname -r) uptime=$(cut -d. -f1 /proc/uptime)s";
         echo "  machine=$(cat /sys/firmware/devicetree/base/model 2>/dev/null | tr -d "\0")";
         echo "  stall=$(journalctl -b -k --no-pager 2>/dev/null | grep -cE "vblank wait timed out|wait_for_vblanks|flip_done timed out") weston=$(systemctl is-active weston) keymapper=$(systemctl is-active r36-keymapper)";
         echo "  dsi=$(cat /sys/class/drm/card0-DSI-1/status 2>/dev/null) blank=$(cat /sys/class/graphics/fb0/blank 2>/dev/null) mem=$(awk "/MemAvailable/{print int(\$2/1024)}" /proc/meminfo)MB"' 2>&1 | tail -5)
  if echo "$out" | grep -q "host="; then
    echo "=== $ip answered ==="
    echo "$out" | sed 's/^/  /'
    case "$out" in
      *r36max2*) echo "  => this is the handheld"; exit 0 ;;
      *) echo "  !! NOT the handheld (wrong host answered) - check the address"; exit 2 ;;
    esac
  fi
done
echo "!! no handheld on ssh yet (tried .209 .210 .208 .211 .1)"
exit 1
