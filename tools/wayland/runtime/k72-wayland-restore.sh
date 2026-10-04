#!/bin/bash
# k72-wayland-restore.sh - the panel went white with dark corners.  Take the
# graphical session apart (keymapper first, then weston), give the console back,
# and record whether the vblank WARN storm stops with it - which tells us the
# stall is on the compositor/page-flip side rather than the panel or panfrost.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 120 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
echo "=== timeline: first and last vblank WARN, and what surrounded the first one ==="
journalctl -b --no-pager -k | grep -n "WARNING: drivers/gpu/drm/drm_atomic_helper.c" |
  head -2 | sed 's/^/  /'
journalctl -b --no-pager -k | grep -c "drm_atomic_helper_wait_for_vblanks" | sed 's/^/  total vblank warnings: /'
FIRST=$(journalctl -b --no-pager -k | grep -m1 "WARNING: drivers/gpu/drm/drm_atomic_helper.c" | awk '{print $1, $2, $3}')
echo "  first warning at: $FIRST"
journalctl -b --no-pager -k --since "$FIRST" ~1 | head -1 >/dev/null 2>&1
echo "  weston lines in the 3 minutes BEFORE the first warning:"
journalctl -u weston --no-pager | awk '$3 >= "10:08" && $3 <= "10:12"' | head -14 | sed 's/^/    /'

echo
echo "=== any page-flip / vblank / plane errors from weston itself ==="
journalctl -u weston --no-pager | grep -iE "flip|vblank|plane|retry|timeout|no modes|GL|renderer|EGL" |
  tail -20 | sed 's/^/  /'

echo
echo "=== taking the session apart ==="
systemctl stop r36-keymapper; echo "  keymapper: $(systemctl is-active r36-keymapper)"
sleep 1
systemctl stop weston; echo "  weston: $(systemctl is-active weston)"
chvt 1 2>/dev/null
echo "  getty@tty1: $(systemctl is-active getty@tty1)   active vt: $(fgconsole 2>/dev/null)"
echo "  fb0 blank flag: $(cat /sys/class/graphics/fb0/blank 2>/dev/null)"
echo "  input nodes now: $(ls /sys/class/input | grep event | tr '\n' ' ')"

echo
echo "=== did the kernel warnings stop? (wait 50s, count again) ==="
A=$(journalctl -b --no-pager -k | grep -c "drm_atomic_helper_wait_for_vblanks")
sleep 50
B=$(journalctl -b --no-pager -k | grep -c "drm_atomic_helper_wait_for_vblanks")
echo "  warnings before 50s wait: $A   after: $B   delta: $((B-A))"
echo "  last kernel warning timestamp: $(journalctl -b --no-pager -k | grep 'WARNING: drivers/gpu/drm' | tail -1 | awk '{print $1,$2,$3}')"
echo "  current time: $(date '+%H:%M:%S')"
echo "  gpu still fine: $(systemctl is-active weston)  dmesg tail:"
dmesg | tail -4 | sed 's/^/    /'
EOS
echo "=== restore done: ask the user whether the console text is back ==="
