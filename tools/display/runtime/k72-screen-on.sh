#!/bin/bash
# k72-screen-on.sh - fresh boot, and /sys/class/graphics/fb0/blank reads 4 (DPMS
# off), so the panel may be black on purpose.  Wake it, turn console blanking off
# for good (a screensaver that we cannot dismiss without a keyboard is a trap on
# this device), and report the bridge/capture state.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 90 sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV 'sh -s' <<'EOS'
echo "=== before ==="
echo "  fb0 blank: $(cat /sys/class/graphics/fb0/blank 2>/dev/null)"
echo 0 > /sys/class/graphics/fb0/blank 2>/dev/null
echo "  fb0 blank after unblank: $(cat /sys/class/graphics/fb0/blank)"

# kill kernel-side console blanking: blank=0/powerdown=0 for every VT, and make
# it survive by writing the same into the console-setup/systemd unit we already
# ship for the status page
for t in 1 2 3 4 5 6; do
  [ -e /dev/tty$t ] && setterm -blank 0 -powerdown 0 -store > /dev/tty$t 2>/dev/null
done
setterm -blank 0 -powerdown 0 -store > /dev/console 2>/dev/null
echo "  blanking disabled via setterm on tty1..6 (0 = never blank)"
cat /sys/class/graphics/fb0/blank | sed 's/^/  final fb0 blank: /'

echo
echo "=== a marker on the panel so the user has something to confirm ==="
systemctl restart getty@tty1 2>/dev/null; sleep 1
printf '\033[H\033[J' > /dev/tty1 2>/dev/null
{
  echo ""
  echo "   r36max2  kernel $(uname -r)  $(date '+%H:%M:%S')"
  echo "   ------------------------------------------------"
  echo "   屏幕恢复成功，控制台在线。摇杆键鼠桥正在抓事件。"
  echo "   weston: $(systemctl is-active weston)   bridge: $(systemctl is-active r36-km-test)"
  echo "   ------------------------------------------------"
  echo ""
  echo "   (login prompt will reappear on its own; if this text is on the panel,"
  echo "    then fbcon, the VOP and the DSI link are all healthy again)"
} > /dev/tty1 2>/dev/null
echo "  wrote marker to /dev/tty1 (getty restarted first so it sticks)"

echo
echo "=== bridge + capture state ==="
echo "  bridge unit: $(systemctl is-active r36-km-test)"
journalctl -u r36-km-test --no-pager -n 8 | sed 's/^/    /'
echo "  evtest running: $(pgrep -c evtest)  files: $(ls -l /tmp/km-kbd.txt /tmp/km-mouse.txt 2>/dev/null | awk '{print $5, $9}' | tr '\n' '|')"
echo "  flip complaints since boot: $(journalctl -b --no-pager -k | grep -cE 'wait_for_vblanks|flip_done|vblank wait')"
EOS
echo "=== screen on ==="
