#!/bin/bash
# k72-wayland-shot2.sh - push the improved r36-shot.py (wide file search + several
# candidate bindings), put content on the panel, try to capture, pull it back.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
R() { sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV "$@"; }
mkdir -p /mnt/e/ubuntu/shots

sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV "cat > /usr/local/bin/r36-shot.py" \
  < /mnt/e/ubuntu/tools/capture/r36-shot.py
R 'chmod 755 /usr/local/bin/r36-shot.py
   echo "  weston active: $(systemctl is-active weston)  socket: $(ls /run/wayland 2>/dev/null | tr "\n" " ")"'

echo "=== render 30s of content ==="
R 'r36-wayland smoke 30 >/dev/null 2>&1 &
   sleep 3
   echo "  clients: $(pgrep -c -f "weston-simple-egl|weston-flower")"
   echo "=== try to capture ==="
   timeout 90 python3 /usr/local/bin/r36-shot.py /tmp/r36-shot.png
   rc=$?
   echo "  shot rc=$rc"
   ls -l /tmp/r36-shot.png 2>/dev/null | sed "s/^/    /"
   echo "  any png newer than 3 minutes on the card:"
   find / -xdev -name "*.png" -mmin -3 -size +1k 2>/dev/null | head -8 | sed "s/^/    /"'

sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'cat /tmp/r36-shot.png 2>/dev/null' > /mnt/e/ubuntu/shots/r36-weston.png 2>/dev/null
if [ -s /mnt/e/ubuntu/shots/r36-weston.png ]; then
  ls -l /mnt/e/ubuntu/shots/r36-weston.png | sed "s/^/  pulled: /"
else
  echo "  nothing to pull (shots/r36-weston.png empty)"
fi
echo "=== done ==="
