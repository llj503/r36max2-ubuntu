#!/bin/bash
# k72-wayland-shot.sh - render content and try to get a picture of the panel back
# to Windows.  Two attempts: the direct weston-screenshooter request (weston 14
# refuses this with "unauthorized"), then r36-shot.py which injects Super+Print
# through /dev/uinput so the *user* authorises the capture.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
R() { sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV "$@"; }

echo "=== memory while weston + clients run ==="
R 'free -m | sed -n "1,3p" | sed "s/^/  /"; echo "  top consumers:"; ps -o rss=,comm= -C weston,weston-simple-egl,weston-flower,weston-desktop-shell 2>/dev/null | sort -rn | head -6 | sed "s/^/    /"'

echo
echo "=== render something for 25s, then shoot ==="
R 'r36-wayland smoke 25 >/dev/null 2>&1 &
   sleep 3
   echo "  clients up: $(pgrep -c -f "weston-simple-egl|weston-flower")"
   timeout 45 python3 /usr/local/bin/r36-shot.py /tmp/r36-shot.png 2>&1 | sed "s/^/  /"
   ls -l /tmp/r36-shot.png /root/*.png /root/screenshot* 2>/dev/null | sed "s/^/    /"'

echo
echo "=== pull it back ==="
sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'cat /tmp/r36-shot.png' > /mnt/e/ubuntu/shots/r36-weston.png 2>/dev/null
if [ -s /mnt/e/ubuntu/shots/r36-weston.png ]; then
  ls -l /mnt/e/ubuntu/shots/r36-weston.png | sed 's/^/  /'
  python3 -c "
import struct,sys
d=open('/mnt/e/ubuntu/shots/r36-weston.png','rb').read(24)
print('  png header ok:', d[:8]==bytes([0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a]), 'size', struct.unpack('>II', d[16:24]) if d[:8]==bytes([0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a]) else '?')
" 2>/dev/null || head -c 8 /mnt/e/ubuntu/shots/r36-weston.png | od -An -tx1 | sed 's/^/  /'
else
  echo "  no screenshot file came back (see the attempt log above)"
fi
echo "=== shot done ==="
