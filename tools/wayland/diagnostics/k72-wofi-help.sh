#!/bin/bash
# k72-wofi-help.sh - wofi dmenu stays up (rc=124) but grid/list exit instantly.
# Need the *full* stderr (previous run truncated at 160 chars) plus the real option list.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 150 sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV 'sh -s' <<'EOS'
export XDG_RUNTIME_DIR=/run/wayland WAYLAND_DISPLAY=wayland-0
echo "=== full option list ==="
wofi --help 2>&1 | sed 's/^/  /'
echo
echo "=== full stderr for --show grid ==="
printf 'a\nb\nc\n' | timeout 6 wofi --show grid --columns 3 -W 500 -H 260 2>/tmp/g.err; echo "  rc=$?"; cat /tmp/g.err | sed 's/^/  | /'
echo "=== full stderr for --show grid, no columns ==="
printf 'a\nb\nc\n' | timeout 6 wofi --show grid 2>/tmp/g2.err >/dev/null; echo "  rc=$?"; grep -v AT-SPI /tmp/g2.err | sed 's/^/  | /'
echo "=== full stderr for --show dmenu --columns 10 ==="
printf 'abcdefgh\nijklmnop\nqrstuvw\nxyz0123\n' | timeout 6 wofi --show dmenu --columns 10 -W 700 -H 400 2>/tmp/g3.err >/tmp/g3.out; echo "  rc=$? out=[$(tr '\n' ' ' </tmp/g3.out)]"; grep -v AT-SPI /tmp/g3.err | sed 's/^/  | /'
EOS
echo "=== done ==="
