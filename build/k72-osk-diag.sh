#!/bin/bash
# k72-osk-diag.sh - the panel shows nothing, so separate the four possibilities
# before touching anything else: (1) weston died/restarted, (2) the windows exist
# but the panel is blanked (DPMS/backlight), (3) the console owns the VT again,
# (4) the display pipeline wedged (the old flip_done/vblank signature).
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 120 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
echo "=== services / VT owner ==="
echo "  weston=$(systemctl is-active weston) getty@tty1=$(systemctl is-active getty@tty1.service) r36-keymapper=$(systemctl is-active r36-keymapper)"
echo "  foreground vt=$(fgconsole 2>/dev/null || echo unknown)   weston unit: $(systemctl show weston -p SubState,ExecMainPID,Result 2>/dev/null | tr '\n' ' ')"
echo "  processes: $(ps -o pid=,etime=,comm= -C weston,foot,wofi 2>/dev/null | tr '\n' ' ')"
echo "  wayland socket: $(ls /run/wayland 2>&1 | tr '\n' ' ')"
echo
echo "=== panel power ==="
ls /sys/class/backlight 2>&1 | sed 's/^/  backlight dirs: /'
for d in /sys/class/backlight/*; do
  [ -d "$d" ] || continue
  echo "  $(basename $d): brightness=$(cat $d/brightness 2>/dev/null)/$(cat $d/max_brightness 2>/dev/null) power=$(cat $d/bl_power 2>/dev/null) act=$(cat $d/actual_brightness 2>/dev/null)"
done
ls -d /sys/class/drm/card0-* 2>/dev/null | sed 's/^/  conn: /'
for c in /sys/class/drm/card0-*/status /sys/class/drm/card0-*/power_state /sys/class/drm/card0-*/enabled; do
  [ -r "$c" ] && echo "  ${c##*/card0-} = $(cat $c)"
done 2>/dev/null | head -12
echo
echo "=== kernel: display pipeline ==="
echo "  flip/vblank stall messages since boot: $(journalctl -b -k --no-pager 2>/dev/null | grep -cE 'wait_for_vblanks|flip_done timed out|vblank wait timed out|commit wait timed out')"
journalctl -b -k --no-pager 2>/dev/null | grep -E 'rockchip-drm|vop|drm' | tail -6 | sed 's/^/     /'
mountpoint -q /sys/kernel/debug || mount -t debugfs nodev /sys/kernel/debug 2>/dev/null
if [ -r /sys/kernel/debug/dri/0/summary ]; then
  echo "  --- DSI connector + CRTC state (proves whether a mode is scanning out) ---"
  awk '/Connector DSI-1/,/^$/' /sys/kernel/debug/dri/0/summary | sed -n '1,14p' | sed 's/^/     /'
  awk '/^plane\[/' /sys/kernel/debug/dri/0/summary | head -6 | sed 's/^/     /'
  awk '/crtc\[/{f=1} f' /sys/kernel/debug/dri/0/summary | sed -n '1,10p' | sed 's/^/     /'
else
  echo "  (no /sys/kernel/debug/dri/0/summary)"
fi
echo
echo "=== weston journal (last 25) ==="
journalctl -u weston --no-pager -n 25 | sed 's/^/     /'
echo
echo "=== osk / foot logs ==="
tail -4 /tmp/osk.log 2>/dev/null | sed 's/^/  osk: /'
tail -4 /tmp/foot-osk.log 2>/dev/null | sed 's/^/  foot: /'
echo "  typed bytes so far: $(wc -c < /tmp/osk-typed.txt 2>/dev/null || echo 0)"
EOS
echo "=== diag done ==="
