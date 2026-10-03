#!/bin/bash
# k72-osk-settle-bisect.sh - find the smallest --settle that reliably lands a
# character in the previous window.
#
# Measured so far (one pick each): 0.15 lost, 0.6 lost, 1.5 landed.  That is
# weston needing well over half a second after the menu surface disappears before
# the old surface owns the keyboard again.  This runs 3 picks per value so a single
# lucky timing does not set the default.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 420 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
export XDG_RUNTIME_DIR=/run/wayland WAYLAND_DISPLAY=wayland-0
content() { cat /tmp/osk-typed.txt 2>/dev/null | tr -d '\n'; }

echo "  host=$(hostname)  weston=$(systemctl is-active weston)"
systemctl is-active weston >/dev/null || systemctl restart weston
sleep 3
pkill -x foot 2>/dev/null; pkill -x wofi 2>/dev/null; pkill -f "bin/r36-osk" 2>/dev/null
sleep 1
: > /tmp/osk-typed.txt
(setsid timeout 900 foot --title=osktarget -- /bin/sh -c \
  'stty -icanon min 1 time 0 2>/dev/null; while :; do cat >> /tmp/osk-typed.txt; sleep 1; done' \
  >/tmp/foot-osk.log 2>&1 &)
sleep 3
echo "  foot=$(pgrep -cx foot)"

check() {   # check <settle> <picks>
  S=$1; N=$2
  pkill -f "bin/r36-osk" 2>/dev/null; pkill -x wofi 2>/dev/null; sleep 1
  (setsid timeout 180 /usr/local/bin/r36-osk --settle $S --pick-timeout 90 >/tmp/osk.log 2>&1 &)
  sleep 4
  before=$(content)
  i=0
  while [ $i -lt "$N" ]; do
    # ENTER resubmits whatever is highlighted; one DOWN first so two picks in a
    # row are never the very same cell
    /usr/local/bin/r36-osk --keys DOWN,DOWN,ENTER >/dev/null 2>&1
    sleep 3
    i=$((i + 1))
  done
  picks=$(grep -cE '^  \[' /tmp/osk.log)
  got=$(content)
  echo "  settle=$S  picks=$picks  landed=${#got} chars=[$got]"
}

echo "=== 3 picks per settle value ==="
for S in 0.8 1.0 1.2 1.5; do
  check $S 3
done
echo
echo "  foot=$(pgrep -cx foot) wofi=$(pgrep -cx wofi) stall=$(journalctl -b -k --no-pager | grep -cE 'vblank wait timed out|wait_for_vblanks|flip_done timed out')"
EOS
echo "=== settle bisect done: pick the smallest value where landed == 3 ==="
