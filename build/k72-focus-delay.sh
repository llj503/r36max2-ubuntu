#!/bin/bash
# k72-focus-delay.sh - measure weston's focus-restore delay by itself.
#
# The settle bisect (0.8/1.0/1.2/1.5 s -> 0/1/1/1 of 3 picks landed) says this is
# not a threshold problem, so stop guessing inside the keyboard and measure the
# primitive: map a wofi window, kill it, and type one DISTINCT character at a
# known delay after the kill.  Whichever letters show up in the capture file tells
# exactly how long the previous surface takes to own the keyboard again - and
# whether that is deterministic at all.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 300 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
export XDG_RUNTIME_DIR=/run/wayland WAYLAND_DISPLAY=wayland-0
content() { cat /tmp/osk-typed.txt 2>/dev/null | tr -d '\n'; }

echo "  host=$(hostname) weston=$(systemctl is-active weston)"
systemctl is-active weston >/dev/null || systemctl restart weston
sleep 3
pkill -x foot 2>/dev/null; pkill -x wofi 2>/dev/null; pkill -f "bin/r36-osk" 2>/dev/null
sleep 1
: > /tmp/osk-typed.txt
(setsid timeout 900 foot --title=osktarget -- /bin/sh -c \
  'stty -icanon min 1 time 0 2>/dev/null; while :; do cat >> /tmp/osk-typed.txt; sleep 1; done' \
  >/tmp/foot-osk.log 2>&1 &)
sleep 3
echo "  foot=$(pgrep -cx foot)  baseline=[$(content)]"
echo "  control: type 'A' with no menu anywhere on screen"
/usr/local/bin/r36-osk --type 'A' >/dev/null 2>&1
sleep 1
echo "  now=[$(content)]  (A must be there or the target itself is the problem)"

i=1
echo
echo "=== kill the menu, wait T, type one letter ==="
for T in 0.2 0.4 0.7 1.0 1.5 2.5; do
  L=$(printf "%c" $((96 + i)))          # b, c, d, e, f, g
  (setsid wofi --show dmenu --normal-window --columns 10 --width 940 --height 460 \
     --hide-search --style /run/r36-osk.css --prompt "focus-probe $T" \
     <<<"x
y
z" >/dev/null 2>&1 &)
  sleep 2
  [ "$(pgrep -cx wofi)" = 1 ] || { echo "  T=$T  !! wofi did not map - cannot measure"; i=$((i+1)); continue; }
  pkill -x wofi
  sleep $T
  before=$(content)
  /usr/local/bin/r36-osk --type "$L" >/dev/null 2>&1
  sleep 0.6
  after=$(content)
  if [ "$after" != "$before" ]; then v="LANDED"; else v="LOST"; fi
  echo "  T=${T}s  typed '$L'  file=[$after]  => $v"
  sleep 1
  i=$((i + 1))
done
echo
echo "  final=[$(content)]  foot=$(pgrep -cx foot) stall=$(journalctl -b -k --no-pager | grep -cE 'vblank wait timed out|wait_for_vblanks|flip_done timed out')"
EOS
echo "=== focus-delay measurement done ==="
