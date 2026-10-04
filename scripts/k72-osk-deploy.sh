#!/bin/bash
# k72-osk-deploy.sh - install r36-osk on the running board and prove, without
# needing anyone to click, that all three grids actually map under weston.
# rc=124 from a timeout-wrapped wofi is the success signal here.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
SRC=/mnt/e/ubuntu/packages/r36-osk/r36-osk.py

timeout 90 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV "cat > /usr/local/bin/r36-osk" < "$SRC" || { echo "!! upload failed"; exit 1; }
timeout 200 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
chmod 755 /usr/local/bin/r36-osk
echo "  syntax: $(python3 -c 'import py_compile; py_compile.compile("/usr/local/bin/r36-osk", doraise=True)' 2>&1 && echo ok)"
echo "  weston=$(systemctl is-active weston)"
echo
echo "=== pages ==="
/usr/local/bin/r36-osk --list
echo
echo "=== probe each grid for 6s: rc=124-equivalent means the window stayed up ==="
export XDG_RUNTIME_DIR=/run/wayland WAYLAND_DISPLAY=wayland-0
for p in letters symbols nav; do
  /usr/local/bin/r36-osk --start $p --probe-grid 6
  echo "    -> rc=$?"
done
echo
echo "=== uinput side: create keyboard, tap one key, destroy ==="
/usr/local/bin/r36-osk --type 'x' 2>&1 | sed 's/^/  /'
echo "  weston log tail:"
journalctl -u weston --no-pager -n 4 | sed 's/^/     /'
echo "  stray processes: $(pgrep -a -f 'r36-osk|wofi' | tr '\n' ' ')"
EOS
echo "=== osk deploy/verify done ==="
