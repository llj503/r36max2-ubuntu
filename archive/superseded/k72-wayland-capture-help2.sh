#!/bin/bash
# k72-wayland-capture-help2.sh - why does weston answer "unauthorized" to a
# screenshooter request, and is there a switch for it.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 90 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
echo "=== weston-screenshooter usage ==="
weston-screenshooter --help 2>&1 | head -12 | sed 's/^/  /'
echo
echo "=== the interface XML, if shipped ==="
find /usr/share -name "*screenshooter*" -o -name "*screenshot*.xml" 2>/dev/null | head -5 | sed 's/^/  /'
echo
echo "=== strings around the denial ==="
for f in /usr/lib/aarch64-linux-gnu/weston/*.so /usr/lib/aarch64-linux-gnu/libweston-14*/*.so /usr/lib/aarch64-linux-gnu/libweston*.so*; do
  [ -e "$f" ] || continue
  strings -a "$f" 2>/dev/null | grep -iE "unauthoriz|screen.capture|capture" | sort -u | sed "s|^|  $(basename $f): |"
done | head -25
echo
echo "=== config keys the compositor reads (grep for ini section names) ==="
for f in /usr/lib/aarch64-linux-gnu/weston/*.so /usr/lib/aarch64-linux-gnu/libweston-14*/*.so /usr/lib/aarch64-linux-gnu/libweston*.so*; do
  [ -e "$f" ] || continue
  strings -a "$f" 2>/dev/null | grep -xE "[a-z][a-z0-9_-]{3,24}" | sort -u |
    grep -iE "^(allow|require|capab|lock|screenshot|capture|restrict|shell|idle)" | sed "s|^|  |"
done | sort -u | head -30
echo
echo "=== weston packages installed (the screenshooter may live elsewhere) ==="
dpkg -l | grep -i weston | awk '{print "  " $2 " " $3}'
EOS
echo "=== done ==="
