#!/bin/bash
# k72-vdbg-read.sh - read the result of the drm.debug reproduction that the previous
# run's tail cut off: what the probe actually printed, whether its unit timed out or
# exited, which atomic commits completed, and the vop interrupt movement.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 120 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
echo "  host=$(hostname) uptime=$(cut -d. -f1 /proc/uptime)s weston=$(systemctl is-active weston)"
echo "  stall since boot=$(journalctl -b -k --no-pager 2>/dev/null | grep -cE 'vblank wait timed out|wait_for_vblanks|flip_done timed out')"
echo "  vblankoffdelay=$(cat /sys/module/drm/parameters/vblankoffdelay) drm.debug=$(cat /sys/module/drm/parameters/debug)"
echo
echo "=== /tmp/vdbg.log (the probe, unbuffered this time) ==="
cat -n /tmp/vdbg.log 2>/dev/null | head -25 || echo "  (no log)"
echo "  log bytes: $(wc -c < /tmp/vdbg.log 2>/dev/null || echo 0)"
echo
echo "=== the vdbg unit's fate ==="
journalctl -b --no-pager -u vdbg.service 2>/dev/null | tail -8 | sed 's/^/     /'
echo
echo "=== every 'updating vblank count' burst boundary (where interrupts started/stopped) ==="
journalctl -b -k --no-pager 2>/dev/null | grep "updating vblank count" | awk '{print $1,$2,$3}' | head -3 | sed 's/^/  first: /'
journalctl -b -k --no-pager 2>/dev/null | grep "updating vblank count" | awk '{print $1,$2,$3}' | tail -3 | sed 's/^/  last:  /'
echo "  total such lines: $(journalctl -b -k --no-pager 2>/dev/null | grep -c 'updating vblank count')"
echo "  highest software count seen: $(journalctl -b -k --no-pager 2>/dev/null | grep -oE 'current=[0-9]+' | tail -1)"
echo
echo "=== the atomic commits around it ==="
journalctl -b -k --no-pager 2>/dev/null | grep -E "drm_atomic_commit\]|drm_atomic_check_only|vblank wait|wait_for_vblanks" | tail -12 | sed 's/^/     /'
echo
echo "=== is the vop interrupt still ticking right now (console only, weston up)? ==="
a=$(awk '/vop/{for(i=2;i<=NF;i++) if($i ~ /^[0-9]+$/) {print $i; exit}}' /proc/interrupts)
sleep 3
b=$(awk '/vop/{for(i=2;i<=NF;i++) if($i ~ /^[0-9]+$/) {print $i; exit}}' /proc/interrupts)
echo "     $a -> $b (delta $((b-a)))"
EOS
echo "=== read done ==="
