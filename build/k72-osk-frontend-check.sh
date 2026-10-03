#!/bin/bash
# k72-osk-frontend-check.sh - wofi dgrid died with "Compositor does not support wlr_layer_shell
# protocol, switching to normal window mode" + "I would love to show dgrid but Idk what it is":
# weston has no layer-shell AND this wofi does not know that mode name.  Find a front-end that
# actually maps a window here: wofi's other modes, bemenu (xdg-shell based), or plain dmenu.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 180 sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV 'sh -s' <<'EOS'
export XDG_RUNTIME_DIR=/run/wayland WAYLAND_DISPLAY=wayland-0
echo "=== what is installed ==="
for b in wofi bemenu dmenu foot weston-simple-dmabuf; do
  printf "%-10s %s\n" "$b" "$(command -v $b || echo MISSING)"
done
echo "  bemenu backend libs: $(ls /usr/lib/*/bemenu 2>/dev/null | tr '\n' ' ')"
echo "  Xwayland: $(command -v Xwayland || echo none)"
echo "  wofi version: $(wofi --version 2>&1 | head -2 | tr '\n' ' ')"
echo "  wofi mode names:"
wofi --help 2>&1 | grep -A3 -iE 'show' | sed 's/^/     /' | head -12
echo
pick() {   # pick <label> <seconds> <cmd...>   rc=124 => window stayed up and waited
  local label=$1 secs=$2; shift 2
  printf 'alpha\nbeta\ngamma\ndelta\n' | timeout "$secs" "$@" >/tmp/fc.out 2>/tmp/fc.err
  local rc=$?
  echo "  [$label] rc=$rc  out=[$(tr '\n' ' ' </tmp/fc.out)]  err=[$(head -c 160 /tmp/fc.err | tr '\n' ' ')]"
}
echo "=== blocking runs: rc=124 means the grid came up and waited for a click ==="
pick "wofi grid"      7 wofi --show grid --columns 4 -W 500 -H 260
pick "wofi list"      7 wofi --show list -W 300 -H 260
pick "wofi dmenu"     7 wofi --show dmenu -W 500 -H 60
pick "bemenu list"    7 bemenu -l 2
pick "bemenu grid"    7 bemenu -a grid -g 4 -l 2
echo
echo "  weston log tail:"
journalctl -u weston --no-pager -n 8 | sed 's/^/     /'
EOS
echo "=== frontend check done ==="
