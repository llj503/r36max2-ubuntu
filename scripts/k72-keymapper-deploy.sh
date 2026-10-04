#!/bin/bash
# k72-keymapper-deploy.sh - install the joypad->mouse/keyboard bridge, start it
# with weston, prove the kernel actually created the two uinput devices, and open
# a capture window on them so the user can press things and we can read what the
# bridge emitted (same async pattern as k72-evcap/k72-evread).
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
WIN=${1:-150}
R() { sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV "$@"; }
PUT() { sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV "cat > $1"; }

echo "=== [0] selftest in the repo copy (no devices touched) ==="
python3 /mnt/e/ubuntu/packages/r36-keymapper/r36-keymapper.py --selftest | sed 's/^/  /'

echo
echo "=== [1] install ==="
PUT /usr/local/bin/r36-keymapper.py < /mnt/e/ubuntu/packages/r36-keymapper/r36-keymapper.py
PUT /etc/systemd/system/r36-keymapper.service < /mnt/e/ubuntu/packages/r36-keymapper/r36-keymapper.service
R 'chmod 755 /usr/local/bin/r36-keymapper.py
   chmod 644 /etc/systemd/system/r36-keymapper.service
   python3 -m py_compile /usr/local/bin/r36-keymapper.py && echo "  compiles ok"
   systemctl daemon-reload
   systemctl enable r36-keymapper 2>&1 | tail -1 | sed "s/^/  enable: /"
   echo "  unit: enabled=$(systemctl is-enabled r36-keymapper) active=$(systemctl is-active r36-keymapper)"'

echo
echo "=== [2] make sure weston is up, which pulls the bridge in ==="
R 'r36-wayland start >/dev/null 2>&1
   systemctl restart r36-keymapper
   sleep 3
   echo "  weston: $(systemctl is-active weston)   keymapper: $(systemctl is-active r36-keymapper)"
   echo "  journal:"; journalctl -u r36-keymapper --no-pager -n 8 | sed "s/^/     /"'

echo
echo "=== [3] did uinput really create two devices? ==="
R 'for d in /sys/class/input/event*; do
     n=$(cat $d/device/name 2>/dev/null)
     case "$n" in "r36 joypad "*) echo "  $(basename $d) = $n";; esac
   done
   echo "  all input nodes: $(ls /sys/class/input | grep event | tr "\n" " ")"
   echo "  weston noticed:"; journalctl -u weston --no-pager -n 12 | grep -iE "r36 joypad|keyboard|mouse|device is a" | tail -6 | sed "s/^/     /"
   echo "  grab state of the joypad node: $(fuser /dev/input/by-path/platform-rocknix-singleadc-joypad-event-joystick 2>&1 | head -1)"'

echo
echo "=== [4] open a ${WIN}s capture window on both new devices ==="
R 'pkill -x evtest 2>/dev/null; sleep 1
   rm -f /tmp/km-kbd.txt /tmp/km-mouse.txt
   KBD=$(for d in /sys/class/input/event*; do [ "$(cat $d/device/name 2>/dev/null)" = "r36 joypad keyboard" ] && basename $d; done)
   MOU=$(for d in /sys/class/input/event*; do [ "$(cat $d/device/name 2>/dev/null)" = "r36 joypad mouse" ] && basename $d; done)
   echo "  keyboard node: ${KBD:-MISSING}   mouse node: ${MOU:-MISSING}"
   [ -n "$KBD" ] && ( timeout $WIN evtest /dev/input/$KBD > /tmp/km-kbd.txt 2>&1 & )
   [ -n "$MOU" ] && ( timeout $WIN evtest /dev/input/$MOU > /tmp/km-mouse.txt 2>&1 & )
   echo "  capturing ${WIN}s starting $(date +%H:%M:%S)"'
echo "=== deployed; now move the left stick and press buttons, then read with k72-keymapper-read.sh ==="
