#!/bin/bash
# k72-final-state.sh - one clean readout of where the machine sits after all this:
# bridge stopped (so the joypad is a normal joystick again), weston off, console
# awake, joypad node present.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 90 sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV 'sh -s' <<'EOS'
echo "  kernel    : $(uname -r)   uptime $(cut -d' ' -f1 /proc/uptime)s"
echo "  weston    : $(systemctl is-active weston) / enabled=$(systemctl is-enabled weston 2>&1)"
echo "  keymapper : persistent=$(systemctl is-active r36-keymapper) transient=$(systemctl is-active r36-km-test)"
echo "  uinput left: $(for d in /sys/class/input/event*; do n=$(cat $d/device/name 2>/dev/null); case "$n" in "r36 joypad"*) echo -n "$d "; esac; done)"
echo "  by-path   : $(ls /dev/input/by-path/ 2>/dev/null | tr '\n' ' ')"
echo "  js0       : $(ls /dev/input/js* 2>/dev/null | tr '\n' ' ')"
echo "  console   : fgconsole=$(fgconsole) fb0blank=$(cat /sys/class/graphics/fb0/blank) getty=$(systemctl is-active getty@tty1)"
echo "  cmdline   : $(cat /proc/cmdline)"
echo "  flip errs since boot: $(journalctl -b --no-pager -k | grep -cE 'wait_for_vblanks|flip_done|vblank wait')"
echo "  failed    : $(systemctl --failed --no-legend --plain | wc -l) units"
echo "  mem       : $(free -m | sed -n 2p)"
echo "  joystick still readable? (2s of js0 input via evtest on event2):"
timeout 2 evtest --query /dev/input/event2 EV_KEY BTN_SOUTH 2>&1 | head -2 | sed 's/^/    /'
EOS
echo "=== state check done ==="
