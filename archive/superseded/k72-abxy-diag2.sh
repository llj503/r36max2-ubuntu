#!/bin/bash
# k72-abxy-diag2.sh - same question, no quoting traps: one ssh session, script fed
# in on stdin so the remote shell sees exactly these lines.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}

timeout 90 sshpass -p $PW ssh -o ConnectTimeout=15 root@$DEV 'sh -s' <<'EOS'
mount -t debugfs none /sys/kernel/debug 2>/dev/null
echo "=== A. all 17 consumers the joypad claimed ==="
grep -E "DPAD|BTN|rumble|amux" /sys/kernel/debug/gpio | cat -A | sed "s/\$$//" | sed "s/^/  /" | head -25
echo
echo "  claimed button lines: $(grep -cE "DPAD|BTN" /sys/kernel/debug/gpio)"
echo
echo "=== B. face-key pads on gpio3, sampled over 6s ==="
i=0
while [ $i -lt 12 ]; do
  i=$((i+1))
  echo -n "  t$i:"
  sed -n '/gpiochip3:/,$p' /sys/kernel/debug/gpio | awk '$1 ~ /^gpio-(16|17|18|19)$/ {printf " %s=%s%s", $1, $4, ($6=="ACTIVE"?"~":"")}'
  echo
  sleep 0.5
done
echo
echo "=== C. gpio3 line 16..19 in the whole dump (with their labels) ==="
sed -n '/gpiochip3:/,/gpiochip4:/p' /sys/kernel/debug/gpio | grep -E "gpio-(1[6-9]) " | sed "s/^/  /"
echo
echo "=== D. is anything else holding those pins? (pinctrl holders) ==="
grep -n "gpio-3 " /sys/kernel/debug/gpio >/dev/null 2>&1
cat /sys/kernel/debug/pinctrl/pinctrl-rockchip-gpio/pins 2>/dev/null | grep -E "pin  (9[6-9]|10[0-1]) " | sed "s/^/  /"
echo
echo "  uptime: $(cut -d' ' -f1 /proc/uptime)s   kernel: $(uname -r)"
EOS

echo
echo "=== E. what the board DTS assigns the face keys to ==="
grep -n -A4 "sw5 {\|sw6 {\|sw7 {\|sw8 {" /mnt/e/ubuntu/projects/r36max2/dt/rk3326-xifan-r36max2.dts | sed "s/^/  /"
echo "  --- every use of gpio3 PC0..PC3 anywhere in the DT ---"
grep -n "gpio3 RK_PC[0-3]" /mnt/e/ubuntu/projects/r36max2/dt/rk3326-xifan-r36max2.dts | sed "s/^/  /"
echo "  --- the pinctrl group the joypad applies ---"
grep -n -A22 "btn_pins_ctrl:" /mnt/e/ubuntu/projects/r36max2/dt/rk3326-xifan-r36max2.dts | head -30 | sed "s/^/  /"
echo "=== abxy diag2 done ==="
