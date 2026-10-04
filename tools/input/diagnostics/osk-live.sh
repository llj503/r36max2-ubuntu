#!/bin/bash
# osk-live.sh - put the on-screen keyboard and a text target on the panel.
#
# Two lessons are baked in:
#  * the grid keeps keyboard focus, so the joystick's own keys drive it:
#    D-pad moves the highlight and START picks.  That is a far better fit for this
#    hardware than aiming a pointer at a 94x82 px cell - proved by injecting
#    DOWN,DOWN,DOWN,ENTER through a second uinput keyboard and watching r36-osk
#    log the resulting pick ("shift on").
#  * the capture target must not exit: `foot -- sh -c 'echo ...; cat > f'` died
#    silently once (foot=0) and every later keystroke went nowhere, which reads as
#    "the keyboard is broken" when it is the test rig.
#
# It also refuses to start a clicking test while the kernel shows flip/vblank
# stalls, because then the panel is frozen on a stale frame and nothing anyone
# clicks can be seen.  Stop with:  pkill -f r36-osk; pkill -x foot
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 150 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'cat > /usr/local/bin/r36-osk' \
  < /mnt/e/ubuntu/packages/r36-osk/r36-osk.py || { echo "!! upload failed"; exit 1; }
timeout 150 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
echo "  host=$(hostname)"
export XDG_RUNTIME_DIR=/run/wayland WAYLAND_DISPLAY=wayland-0
chmod 755 /usr/local/bin/r36-osk
stall=$(journalctl -b -k --no-pager 2>/dev/null | grep -cE 'vblank wait timed out|wait_for_vblanks|flip_done timed out')
echo "  weston=$(systemctl is-active weston) keymapper=$(systemctl is-active r36-keymapper) stall=$stall"
if [ "$stall" != 0 ]; then
  echo "  !! pipeline stalled: the panel would show a stale frame. Reboot first."
  exit 3
fi
systemctl is-active weston >/dev/null || systemctl restart weston
systemctl is-active r36-keymapper >/dev/null || systemctl restart r36-keymapper
sleep 3
rm -f /tmp/osk-typed.txt /tmp/osk.log
: > /tmp/osk-typed.txt
pkill -f "r36-osk" 2>/dev/null; pkill -x wofi 2>/dev/null; pkill -x foot 2>/dev/null; sleep 1
(setsid timeout 3600 foot --title=r36-osk-target -- /bin/sh -c \
  'stty -icanon min 1 time 0 2>/dev/null; while :; do cat >> /tmp/osk-typed.txt; sleep 1; done' \
  >/tmp/foot-osk.log 2>&1 &)
sleep 3
(setsid timeout 3600 /usr/local/bin/r36-osk --pick-timeout 120 > /tmp/osk.log 2>&1 &)
sleep 5
echo "  osk log:"; tail -6 /tmp/osk.log 2>/dev/null | sed 's/^/     /'
echo "  processes (all three must be listed):"
ps -o pid=,etime=,comm= -C weston,foot,wofi 2>/dev/null | sed 's/^/     /'
for want in foot wofi; do
  pgrep -x $want >/dev/null || { echo "  !! $want is not up - the test rig is broken, do not start pressing keys"; exit 4; }
done
echo "  started at $(date +%H:%M:%S)"
EOS
rc=$?
[ $rc -ne 0 ] && exit $rc
cat <<'HOWTO'
=== 屏幕上：foot 窗口 + 10 列 x 5 行网格 ===
主推用法（不需要指针对准）：
  * **方向键**移动高亮格，**START** 选定那个键 —— 选完网格会关掉再重开，一次一个字符
  * **SELECT** = 取消/退出，**MODE**(Super) 也可以当 ESC 用
  * 想用指针也行：左摇杆移动、A 键点击
  * 网格里 ABC / #!? / nav 换页，SHFT 只作用于下一个键，CAPS 切换
按 5~8 个键就够（比如把光标移到 h 按 START，几次），不用按回车，我直接读回比对。
HOWTO
