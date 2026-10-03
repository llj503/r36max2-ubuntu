#!/bin/bash
# k72-console-restore.sh - weston failed to stop cleanly (systemd marked it
# "failed"), getty@tty1 is still inactive because of the Conflicts=, and the panel
# is showing a frozen frame.  Kill the remnants, hand the DRM master back, bring
# the text console back on tty1, and prove whether the kernel is still stalling on
# vblank waits with weston gone.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 120 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
echo "=== weston remnants ==="
pgrep -a weston | sed 's/^/  /' || echo "  none"
pkill -9 -x weston 2>/dev/null; sleep 2
systemctl reset-failed weston r36-keymapper 2>/dev/null
echo "  weston now: $(systemctl is-active weston)   keymapper: $(systemctl is-active r36-keymapper)"

echo
echo "=== bring the console back ==="
systemctl restart getty@tty1; sleep 2
echo "  getty@tty1: $(systemctl is-active getty@tty1)"
chvt 1; sleep 1
echo "  active vt : $(fgconsole 2>/dev/null)"
echo "  fb0 blank : $(cat /sys/class/graphics/fb0/blank 2>/dev/null) (0 = unblanked)"
echo "  drm master: $(ls -l /proc/$(pgrep -x weston 2>/dev/null || echo 1)/fd 2>/dev/null | grep -c dri) (weston gone)"
echo "  panel     : $(cat /sys/class/drm/card0-DSI-1/status) $(cat /sys/class/drm/card0-DSI-1/modes 2>/dev/null | head -1)"
echo "  input nodes: $(ls /sys/class/input | grep event | tr '\n' ' ')"
echo "  joypad grabbed? (should be free again): $(ls -l /sys/class/input/event2/device 2>/dev/null | head -1)"

echo
echo "=== do the vblank warnings continue with weston gone? ==="
A=$(journalctl -b --no-pager -k | grep -c "wait_for_vblanks")
sleep 55
B=$(journalctl -b --no-pager -k | grep -c "wait_for_vblanks")
echo "  warnings: $A -> $B (delta $((B-A)))   now $(date +%H:%M:%S)"
echo "  last warning: $(journalctl -b --no-pager -k | grep 'WARNING: drivers/gpu/drm' | tail -1 | awk '{print $1,$2,$3}')"
echo "  dmesg tail:"; dmesg | tail -5 | sed 's/^/    /'
echo "  free: $(free -m | sed -n 2p)"
EOS
echo "=== console restore done ==="
