#!/bin/bash
# k72-bootcheck.sh - the panel console is up but shows a DSI "cmd queue crashed"
# error.  Pull everything needed to tell whether 7.2.8 is actually running and
# what the DSI/panel/GPU stack did.
set -uo pipefail
PW=ubuntu
DEV=""
for ip in 192.168.31.209 192.168.31.210 192.168.31.208 192.168.31.211; do
  sshpass -p $PW ssh -o ConnectTimeout=5 root@$ip 'echo ok' >/dev/null 2>&1 && { DEV=$ip; break; }
done
[ -n "$DEV" ] || { echo "device not reachable on the usual addresses"; exit 1; }
echo "device: $DEV"
S() { sshpass -p $PW ssh -o ConnectTimeout=15 root@$DEV "$@" </dev/null 2>/dev/null; }

echo "=== identity ==="
S 'echo "  kernel : $(uname -r)"; echo "  uptime : $(cut -d" " -f1 /proc/uptime)s"; echo "  cmdline: $(cat /proc/cmdline)"'
echo "=== the DSI error in context ==="
S 'dmesg | grep -inE "cmd queue|dsi|panel|mipi" | head -25 | sed "s/^/  /"'
echo "=== DRM / GPU ==="
S 'dmesg | grep -iE "drm|vop|panfrost|display-subsystem" | head -25 | sed "s/^/  /"'
echo "=== errors and warnings (whole boot) ==="
S 'dmesg | grep -iE "error|fail|warn|bug|unable|timeout|denied" | grep -viE "audit|apparmor" | head -25 | sed "s/^/  /"'
echo "=== modules actually loaded ==="
S 'lsmod | awk "NR<=14" | sed "s/^/  /"'
echo "=== connector state ==="
S 'for c in /sys/class/drm/*/; do s=$(cat $c/status 2>/dev/null); [ -n "$s" ] && echo "  $(basename $c): $s enabled=$(cat $c/enabled 2>/dev/null)"; done'
echo "=== services ==="
S 'systemctl --failed --no-legend --plain | sed "s/^/  /"; echo "  wlan0: $(ip -4 -br addr show wlan0 2>/dev/null | awk "{print \$2, \$3}")"; echo "  sound: $(ls /dev/snd 2>/dev/null | tr "\n" " ")"'
echo "=== last 25 lines of dmesg ==="
S 'dmesg | tail -25 | sed "s/^/  /"'
