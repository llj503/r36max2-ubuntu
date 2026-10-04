#!/bin/bash
# k72-reboot-then-bridge.sh - reboot to clear the stalled CRTC, prove the display
# pipeline is healthy again, then start the joypad->mouse/keyboard bridge WITHOUT
# weston and open a capture window on the two uinput devices.  Verifying the 17
# mappings does not need a compositor at all - reading what the bridge emits is
# enough, and it keeps the panel out of the experiment.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
WIN=${WIN:-240}
S() { sshpass -p $PW ssh -o ConnectTimeout=8 root@$DEV 'true' 2>/dev/null; }

echo "[$(date +%H:%M:%S)] rebooting $DEV"
sshpass -p $PW ssh -o ConnectTimeout=15 root@$DEV '(sleep 1; reboot) >/dev/null 2>&1 &' 2>/dev/null
for i in $(seq 1 40); do
  sleep 4
  if S; then echo "[$(date +%H:%M:%S)] ssh back after ~$((i*4))s"; break; fi
done
S || { echo "  !! not back after 160s"; exit 1; }

timeout 120 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
echo "=== health after the reboot ==="
echo "  kernel : $(uname -r)   uptime: $(cut -d' ' -f1 /proc/uptime)s"
echo "  console: fgconsole=$(fgconsole 2>/dev/null)  fb0 blank=$(cat /sys/class/graphics/fb0/blank 2>/dev/null)  getty=$(systemctl is-active getty@tty1)"
echo "  panel  : $(cat /sys/class/drm/card0-DSI-1/status) $(cat /sys/class/drm/card0-DSI-1/modes 2>/dev/null | head -1)"
echo "  flip/vblank complaints SINCE THIS BOOT: $(journalctl -b --no-pager -k 2>/dev/null | grep -cE 'wait_for_vblanks|flip_done timed out|vblank wait timed out')"
echo "  weston: $(systemctl is-active weston) (must be inactive)  keymapper: $(systemctl is-active r36-keymapper)"
echo "  joypad: $(lsmod | awk '/joypad/{print $1"="}')  nodes: $(ls /dev/input/by-path/ 2>/dev/null | grep -c rocknix) rocknix entries"
echo "  drm nodes: $(ls /dev/dri | tr '\n' ' ')"
echo "  failed units: $(systemctl --failed --no-legend --plain | wc -l)"
EOS

echo
echo "=== start the bridge as a transient unit (no weston involved) ==="
timeout 120 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<EOS
systemd-run --unit=r36-km-test --quiet /usr/bin/python3 /usr/local/bin/r36-keymapper.py -v
sleep 3
echo "  unit: \$(systemctl is-active r36-km-test)"
journalctl -u r36-km-test --no-pager -n 6 | sed 's/^/    /'
echo "  input nodes: \$(ls /sys/class/input | grep event | tr '\n' ' ')"
KBD=\$(for d in /sys/class/input/event*; do [ "\$(cat \$d/device/name 2>/dev/null)" = "r36 joypad keyboard" ] && basename \$d; done)
MOU=\$(for d in /sys/class/input/event*; do [ "\$(cat \$d/device/name 2>/dev/null)" = "r36 joypad mouse" ] && basename \$d; done)
echo "  keyboard node: \${KBD:-MISSING}   mouse node: \${MOU:-MISSING}"
pkill -x evtest 2>/dev/null; sleep 1
rm -f /tmp/km-kbd.txt /tmp/km-mouse.txt
[ -n "\$KBD" ] && ( timeout $WIN evtest /dev/input/\$KBD > /tmp/km-kbd.txt 2>&1 & )
[ -n "\$MOU" ] && ( timeout $WIN evtest /dev/input/\$MOU > /tmp/km-mouse.txt 2>&1 & )
echo "  capture window ${WIN}s opened at \$(date +%H:%M:%S)"
EOS
echo "=== now move the left stick and press every button; read with k72-keymapper-read.sh ==="
