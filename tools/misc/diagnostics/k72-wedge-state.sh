#!/bin/bash
# k72-wedge-state.sh - is the panel live again after the weston restart?
# Two independent signals: (1) does the kernel still emit vblank/flip stalls while
# weston is up and repainting, (2) put a continuously animating client on screen so
# the user can answer with one word whether anything moves.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 160 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
export XDG_RUNTIME_DIR=/run/wayland WAYLAND_DISPLAY=wayland-0
c0=$(journalctl -b --no-pager -k 2>/dev/null | grep -cE 'vblank wait timed out|wait_for_vblanks|flip_done timed out')
echo "  weston=$(systemctl is-active weston) pid=$(pgrep -x weston | tr '\n' ' ')  vt=$(fgconsole 2>/dev/null)"
echo "  stall count now: $c0"
echo "  last 3 stall timestamps:"
journalctl -b --no-pager -k 2>/dev/null | grep -E 'vblank wait timed out|wait_for_vblanks|flip_done timed out' | tail -3 | sed 's/^/     /'
echo
echo "  starting an animating client (weston-simple-egl, 12s) - the panel should show a spinning triangle"
(setsid timeout 12 weston-simple-egl >/tmp/egl-state.log 2>&1 &)
sleep 3
echo "  egl log: $(head -c 90 /tmp/egl-state.log 2>/dev/null | tr '\n' ' ')"
sleep 10
c1=$(journalctl -b --no-pager -k 2>/dev/null | grep -cE 'vblank wait timed out|wait_for_vblanks|flip_done timed out')
echo "  stall count after the 12s animation window: $c1  (delta $((c1-c0)))"
echo
echo "  weston's own view of the last minute:"
journalctl -u weston --no-pager --since '-70 seconds' 2>/dev/null | tail -8 | sed 's/^/     /'
if [ "$((c1-c0))" -gt 0 ]; then
  echo "  => commits still are not completing: the display pipeline is wedged (needs a reboot)"
else
  echo "  => no new stalls while a GL client was redrawing: pipeline looks alive"
fi
EOS
echo "=== if the panel shows a MOVING triangle, the pipeline recovered without a reboot ==="
