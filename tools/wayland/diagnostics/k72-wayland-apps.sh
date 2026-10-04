#!/bin/bash
# k72-wayland-apps.sh - launch a visible set of Wayland clients inside the weston
# session and prove they stay alive (no crash, no "error connecting to display").
# The remote half is fed as a quoted heredoc so nothing gets re-expanded by the
# local shell (that mangling has bitten this project repeatedly).
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
LONG=${LONG:-600}

timeout 120 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'LONG='"$LONG"' sh -s' <<'EOS'
mkdir -p /tmp/wl-apps
export XDG_RUNTIME_DIR=/run/wayland WAYLAND_DISPLAY=wayland-0
pkill -f 'weston-simple-egl|weston-flower|wofi' 2>/dev/null; sleep 1
(setsid timeout $LONG weston-simple-egl > /tmp/wl-apps/egl.log    2>&1 &)
(setsid timeout $LONG weston-flower     > /tmp/wl-apps/flower.log 2>&1 &)
(setsid timeout $LONG foot              > /tmp/wl-apps/foot.log   2>&1 &)
(setsid timeout $LONG wofi --show dmenu > /tmp/wl-apps/wofi.log   2>&1 &)
sleep 6
echo "  weston: $(systemctl is-active weston)  pid $(systemctl show -p MainPID --value weston)  mem $(systemctl show -p MemoryCurrent --value weston) B"
echo "  resident apps:"
ps -o pid=,rss=,etime=,comm= -C weston,weston-simple-egl,weston-flower,foot,wofi 2>/dev/null | sed 's/^/     /'
echo "  client logs (empty means no complaint):"
for f in /tmp/wl-apps/*.log; do
  printf '     %-10s %s bytes | %s\n' "$(basename $f)" "$(wc -c < $f)" "$(head -c 100 $f | tr '\n' ' ')"
done
echo "  weston journal, last 10:"
journalctl -u weston --no-pager -n 10 | sed 's/^/     /'
echo "  memory: $(sed -n 2p /proc/meminfo)"
echo "  panel : $(cat /sys/class/drm/card0-DSI-1/status) $(cat /sys/class/drm/card0-DSI-1/modes 2>/dev/null | head -1)"
EOS
echo "=== apps will run for ${LONG}s - look at the panel ==="
