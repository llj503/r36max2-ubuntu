#!/bin/bash
# k72-wayland-deploy.sh - push the Wayland plumbing onto the running card (and it
# is the same five files a v20 rootfs needs, so keep them in the repo, not on the
# device).  Starts weston afterwards unless STOP=1.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
SRC=/mnt/e/ubuntu/build
# the whole command is passed as an argument; 'sh -s' would instead swallow this
# script's own stdin and silently run nothing
S() { sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV "$@"; }
# stdin is redirected locally, so the file lands in the remote path
PUT() { sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV "cat > $1"; }

echo "=== [0] make sure the target dirs exist ==="
S 'mkdir -p /etc/xdg/weston /usr/local/bin /etc/profile.d && echo "  dirs ok"'

echo "=== [1] files ==="
PUT /etc/xdg/weston/weston.ini < "$SRC/weston.ini"
PUT /etc/systemd/system/weston.service < "$SRC/weston.service"
PUT /usr/local/bin/r36-wayland < "$SRC/r36-wayland"
PUT /usr/local/bin/r36-shot.py < "$SRC/r36-shot.py"
PUT /etc/profile.d/zz-r36-wayland.sh < "$SRC/zz-r36-wayland.sh"

S 'chmod 755 /usr/local/bin/r36-wayland /usr/local/bin/r36-shot.py
   chmod 644 /etc/xdg/weston/weston.ini /etc/systemd/system/weston.service /etc/profile.d/zz-r36-wayland.sh
   systemctl daemon-reload
   echo "  installed:"
   ls -l /etc/xdg/weston/weston.ini /etc/systemd/system/weston.service /usr/local/bin/r36-wayland /usr/local/bin/r36-shot.py /etc/profile.d/zz-r36-wayland.sh | sed "s/^/    /"
   echo "  unit: enabled=$(systemctl is-enabled weston 2>&1) active=$(systemctl is-active weston 2>&1)"
   python3 -m py_compile /usr/local/bin/r36-shot.py && echo "  r36-shot.py compiles"'

if [ "${1:-}" = "stop" ]; then
  S 'systemctl stop weston 2>/dev/null; echo "  weston stopped"'
  echo "=== deploy done (stopped) ==="; exit 0
fi

echo
echo "=== [2] start it ==="
S 'r36-wayland start
   sleep 2
   echo "  socket: $(ls /run/wayland 2>/dev/null | tr "\n" " ")"
   echo "  weston procs: $(pgrep -c weston)"
   echo "  getty@tty1: $(systemctl is-active getty@tty1)"
   echo "  journal:"
   journalctl -u weston --no-pager -n 14 | sed "s/^/    /"'

echo
echo "=== [3] put something on screen ==="
S 'r36-wayland smoke 8
   sleep 4
   echo "  clients: $(pgrep -af "weston-simple-egl|weston-flower" | tr "\n" "|")"
   echo "  weston tail:"; journalctl -u weston --no-pager -n 6 | sed "s/^/    /"'
echo "=== deploy done: ask the user what the panel shows, then r36-wayland shot ==="
