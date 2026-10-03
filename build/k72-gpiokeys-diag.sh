#!/bin/bash
# k72-gpiokeys-diag.sh - sticks and adc-keys are proven working on 7.2.8, but the
# 17 GPIO buttons produced literally zero events.  Decide which of the two
# possibilities it is: the descriptors were never acquired, or they are acquired
# but the poll loop never reports a change.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
S() { sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV "$@" </dev/null 2>/dev/null; }

echo "=== A. are the 17 button labels present in the gpio core? ==="
S 'mount -t debugfs none /sys/kernel/debug 2>/dev/null
   echo "  lines claimed by a consumer (name = the gpiod label we passed):"
   grep -E "^\s+gpio-" /sys/kernel/debug/gpio | grep -vE "^\s*$" | sed "s/^/    /"
   echo "  -> buttons found: $(grep -cE "DPAD|BTN_" /sys/kernel/debug/gpio)"
   echo "  chips:"; grep -E "^gpiochip" /sys/kernel/debug/gpio | sed "s/^/    /"'

echo
echo "=== B. did the parse loop hit an error for any button? ==="
S 'dmesg | grep -aiE "failed to get gpio|Failed to request|unable to request|error -|gpiod|of_get" | tail -12 | sed "s/^/    /"'
S 'echo "  probe-time messages for the joypad, full:"
   dmesg | grep -a "rocknix-singleadc-joypad" | sed "s/^/    /" | tail -20'

echo
echo "=== C. is the poll loop actually running? sample the joystick node 4x1s ==="
S 'for i in 1 2 3 4; do
     echo -n "  t$i raw js0: "
     timeout 1 jstest --normal /dev/input/js0 2>/dev/null | head -3 | tail -1 | tr -s " "
     echo
   done
   echo "  polldev interval:"; ls /sys/bus/platform/drivers/rocknix-singleadc-joypad/ 2>/dev/null | sed "s/^/    /"
   cat /sys/devices/platform/rocknix-singleadc-joypad/input/input*/uevent 2>/dev/null | sed "s/^/    /"'

echo
echo "=== D. sample the button lines directly, idle then you can press ==="
S 'echo "  sysfs view of the gpiochip the buttons live on (gpio3 = gpiochip640 family):"
   for c in /sys/class/gpio/gpiochip*; do echo "    $(basename $c) base=$(cat $c/base) ngpio=$(cat $c/ngpio) label=$(cat $c/label)"; done'

echo
echo "=== E. what the driver source actually does on IS_ERR for a button ==="
sed -n '985,1035p' /root/r36/k72joypad/rocknix-singleadc-joypad.c
echo "--- the poll function wiring ---"
grep -n -B2 -A12 "poll_dev->poll\s*=\|joypad_poll\|static void joypad_poll" /root/r36/k72joypad/rocknix-singleadc-joypad.c | head -40
echo "=== diag done ==="
