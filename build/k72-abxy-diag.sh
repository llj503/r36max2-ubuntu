#!/bin/bash
# k72-abxy-diag.sh - 13 of 17 buttons now report perfectly, the four face keys
# (BTN_SOUTH/EAST/WEST/NORTH = gpio3 RK_PC0..PC3) still produce nothing.  Find
# out whether the lines are even claimed and what level they sit at.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
S() { sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV "$@" </dev/null 2>/dev/null; }

echo "=== A. every consumer on gpiochip3 (the bank the face keys live on) ==="
S 'mount -t debugfs none /sys/kernel/debug 2>/dev/null
   awk "/gpiochip3:/,/gpiochip4:|^$/" /sys/kernel/debug/gpio | sed "s/^/  /"'

echo
echo "=== B. all 17 button labels, whatever the spelling ==="
S 'grep -cE "DPAD|BTN" /sys/kernel/debug/gpio | sed "s/^/  found: /"
   grep -E "DPAD|BTN" /sys/kernel/debug/gpio | sed "s/^/    /"'

echo
echo "=== C. sample those four pads 12 times over 6s (press A/B/X/Y while this runs) ==="
S 'for i in $(seq 1 12); do
     echo -n "  t$i: "
     awk "/gpiochip3:/,0" /sys/kernel/debug/gpio | grep -E "gpio-16 |gpio-17 |gpio-18 |gpio-19 " | tr -s " " | tr "\n" "|"
     echo
     sleep 0.5
   done'

echo
echo "=== D. what the DT says the face keys are, and the pinctrl group ==="
grep -n -A4 "sw5 {\|sw6 {\|sw7 {\|sw8 {" /mnt/e/ubuntu/board/rk3326-xifan-r36max2.dts | sed "s/^/  /"
echo "  --- btn_pins_ctrl group members ---"
sed -n "/btn_pins_ctrl/,/};/p" /mnt/e/ubuntu/board/rk3326-xifan-r36max2.dts | head -30 | sed "s/^/  /"
echo "  --- pins the panel / other functions claim on gpio3C ---"
grep -n "RK_PC0\|RK_PC1\|RK_PC2\|RK_PC3" /mnt/e/ubuntu/board/rk3326-xifan-r36max2.dts | sed "s/^/  /"

echo
echo "=== E. did the joypad device actually apply its pinctrl default? ==="
S 'echo "  devices with pinctrl in sysfs:"
   ls /sys/devices/platform/rocknix-singleadc-joypad/ 2>/dev/null | sed "s/^/    /"
   echo "  rockchip pinconf/pinmux groups mentioning gpio3C:"
   grep -rn "gpio3 " /sys/kernel/debug/pinctrl/pinctrl-rockchip-gpio/pins 2>/dev/null | grep -E "pin 9[6-9]|pin 10[0-1]" | head -8 | sed "s/^/    /"
   grep -c . /sys/kernel/debug/pinctrl/pinctrl-rockchip-gpio/pins 2>/dev/null | sed "s/^/  pin list lines: /"'
echo "=== abxy diag done ==="
