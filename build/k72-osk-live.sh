#!/bin/bash
# k72-osk-live.sh - put a text target and the on-screen keyboard on the panel.
#
# Two hard lessons are baked in:
#  * it refuses to start a clicking test when the kernel already shows flip/vblank
#    stall messages, because on this board that means the panel is frozen on a
#    stale frame - the windows exist but nobody can see them (that is exactly what
#    happened at 13:20, and the user was told to click a screen that was dead)
#  * the target captures into /tmp/osk-typed.txt in NON-canonical mode, so each
#    character lands in the file immediately instead of waiting for a newline.
#
# Everything is detached.  Stop with:  pkill -f r36-osk; pkill -x foot
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 150 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
export XDG_RUNTIME_DIR=/run/wayland WAYLAND_DISPLAY=wayland-0
stall=$(journalctl -b -k --no-pager 2>/dev/null | grep -cE 'wait_for_vblanks|flip_done timed out|commit wait timed out')
echo "  weston=$(systemctl is-active weston)  keymapper=$(systemctl is-active r36-keymapper)  vt=$(fgconsole 2>/dev/null)"
echo "  kernel flip/vblank stall messages since boot: $stall"
if [ "$stall" != 0 ]; then
  echo "  !! pipeline is stalled - the panel would show a stale frame and a clicking test is"
  echo "  !! pointless.  Reboot (only known recovery on this board), then re-run this script."
  exit 3
fi
systemctl is-active weston >/dev/null || systemctl restart weston
systemctl is-active r36-keymapper >/dev/null || systemctl restart r36-keymapper
sleep 3
rm -f /tmp/osk-typed.txt /tmp/osk.log
pkill -f "r36-osk" 2>/dev/null; pkill -x wofi 2>/dev/null; pkill -x foot 2>/dev/null; sleep 1
(setsid timeout 3600 foot --title=r36-osk-target -- /bin/sh -c \
  'stty -icanon min 1 time 0 2>/dev/null; echo "--- click the grid, characters land here ---" > /dev/tty; cat > /tmp/osk-typed.txt' \
  >/tmp/foot-osk.log 2>&1 &)
sleep 3
(setsid timeout 3600 /usr/local/bin/r36-osk --pick-timeout 120 > /tmp/osk.log 2>&1 &)
sleep 5
echo "  osk log:"; tail -4 /tmp/osk.log 2>/dev/null | sed 's/^/     /'
alive=$(ps -o pid=,etime=,comm= -C weston,foot,wofi 2>/dev/null)
echo "  processes:"; echo "$alive" | sed 's/^/     /'
if ! echo "$alive" | grep -q wofi; then
  echo "  !! no wofi window came up - the grid is not on screen, do not start clicking"
  exit 4
fi
echo "  started at $(date +%H:%M:%S)  (grid re-opens by itself every 120s idle)"
EOS
rc=$?
[ $rc -ne 0 ] && exit $rc
cat <<'HOWTO'
=== 屏幕上现在应该有：一个 foot 窗口 + 10 列 x 5 行的按键网格 ===
  * 左摇杆移动光标，A 键点击；点一个键网格会关掉再重开（一次一个字符，设计如此）
  * 每点一个字符，它会立刻出现在 foot 里（我已改成非缓冲读取，SSH 端能直接读回）
  * SHFT 只对下一个键生效；CAPS 切换；状态写在网格顶部
  * ABC / #!? / nav 换页；X 或 Esc 退出键盘
  * 2 分钟没人点网格会自己重开，不会退出
点两三个键就够了，不用按回车，我这边直接核对。
HOWTO
