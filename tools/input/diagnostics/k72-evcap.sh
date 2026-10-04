#!/bin/bash
# k72-evcap.sh - open an event window on ALL FOUR input nodes that matter for the joypad
# chain, so "did he press it, and did it reach the desktop?" can be answered without
# looking at the panel:
#
#   /tmp/evjoy.txt    the raw rocknix-singleadc-joypad (BTN_*, ABS_*)
#   /tmp/evadc.txt    the adc-keys node                (plain KEY_ presses)
#   /tmp/evkbd.txt    the uinput keyboard r36-keymapper makes  ("r36 joypad keyboard")
#   /tmp/evmouse.txt  the uinput mouse r36-keymapper makes     ("r36 joypad mouse")
#
# The two uinput nodes prove the LAST hop.  A button can be alive on the raw device and
# still never reach the desktop, and that failure is invisible from either end alone.  They
# are found by device NAME rather than number because the numbering shifts with whatever
# else is loaded (r36-osk adds nodes too).
#
# evtest 1.36 has NO --raw option: an earlier capture wrote a usage message instead of
# events, which is why "12 lines and no events" kept happening.  The normal output line is
#   Event: time 1790988082.318388, type 1 (EV_KEY), code 304 (BTN_EAST), value 1
# note the comma before "value" - the old regex used ") value" and matched nothing.
#
# Usage:  bash k72-evcap.sh [seconds]     (default 300)
# Read it later with: bash k72-evread.sh  (the window may still be open)
#
# Rewritten to feed the remote script as a quoted heredoc.  The previous version built the
# remote command inside a double-quoted ssh argument full of \$ escapes - the exact shape
# that has several times leaked half a command into WSL and printed THIS PC's hostname and
# uptime as if they came from the board.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
DUR=${1:-300}

timeout $((DUR + 60)) sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV "DUR=$DUR sh -s" <<'EOS'
pkill -x evtest 2>/dev/null
sleep 1
rm -f /tmp/evjoy.txt /tmp/evadc.txt /tmp/evkbd.txt /tmp/evmouse.txt

JOY=/dev/input/by-path/platform-rocknix-singleadc-joypad-event-joystick
ADC=/dev/input/by-path/platform-adc-keys-event

KBD=''
MOUSE=''
for n in /sys/class/input/event*/device/name; do
  nm=$(cat "$n" 2>/dev/null)
  ev=$(echo "$n" | cut -d/ -f5)
  case "$nm" in
    *"joypad keyboard") KBD=/dev/input/$ev ;;
    *"joypad mouse")    MOUSE=/dev/input/$ev ;;
  esac
done

start() {   # start <node> <outfile>
  if [ -e "$1" ] && [ "$1" != "/dev/none" ]; then
    ( timeout "$DUR" evtest "$1" > "$2" 2>&1 & )
    echo "  capturing $1 -> $2"
  else
    echo "  !! no node for $2 (keymapper not running, or the device is named differently)"
  fi
}
start "$JOY" /tmp/evjoy.txt
start "$ADC" /tmp/evadc.txt
start "${KBD:-/dev/none}" /tmp/evkbd.txt
start "${MOUSE:-/dev/none}" /tmp/evmouse.txt

echo "  window: ${DUR}s opened $(date '+%T')  host=$(hostname) uptime=$(cut -d' ' -f1 /proc/uptime)s"
echo "  keymapper=$(systemctl is-active r36-keymapper)  weston=$(systemctl is-active weston)  ES procs=$(pgrep -c -f /root/es/emulationstation 2>/dev/null || echo 0)"
echo "  joypad nodes: $(ls /dev/input/by-path/ 2>/dev/null | tr '\n' ' ')"
echo "  module on card: $(sha256sum /lib/modules/$(uname -r)/extra/rocknix-singleadc-joypad.ko 2>/dev/null | cut -c1-16)"
echo "  loaded: $(lsmod | awk '/joypad/{print $1"="$3" used"}' | tr '\n' ' ')"
mount -t debugfs none /sys/kernel/debug 2>/dev/null
grep -iE 'rumble|amux' /sys/kernel/debug/gpio 2>/dev/null | sed 's/^/  pin: /'
EOS
echo "=== window open - press on the device now, then read with tools/input/diagnostics/k72-evread.sh ==="
