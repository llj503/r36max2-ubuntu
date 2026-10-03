#!/bin/bash
# k72-stop-rumble.sh - make the motor stop, by whatever layer works.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
S() { sshpass -p $PW ssh -o ConnectTimeout=15 root@$DEV "$@" </dev/null 2>/dev/null; }

echo "=== [1] close whoever opened the joypad device ==="
S 'pkill -x evtest; pkill -x jstest; sleep 1; echo "  readers left: $(ps -eo comm= | grep -cE "evtest|jstest")"'

echo "=== [2] what owns the rumble line, and in what state? ==="
S 'mount -t debugfs none /sys/kernel/debug 2>/dev/null
   cat /sys/kernel/debug/gpio 2>/dev/null | grep -iE "gpio-|rumble|amux" | head -20 | sed "s/^/  /"'

echo "=== [3] unload the driver (stops it re-asserting the line) ==="
S 'rmmod rocknix_singleadc_joypad 2>&1 | sed "s/^/  rmmod: /"; lsmod | grep -c joypad | sed "s/^/  joypad modules loaded: /"'

echo "=== [4] drive the physical line high (= logical 0 for an ACTIVE_LOW enable) ==="
S 'if command -v gpioset >/dev/null 2>&1; then
     gpioset -c gpiochip0 15=1 2>&1 | sed "s/^/  gpioset: /" || gpioset gpiochip0 15=1 2>&1 | sed "s/^/  gpioset: /"
   else
     echo "  no gpioset; using sysfs"
     cat /sys/class/gpio/gpiochip*/base 2>/dev/null | head -3 | sed "s/^/    bases: /"
     N=$(grep -m1 -B0 "gpio0" /sys/kernel/debug/gpio 2>/dev/null | awk "{print \$2}" | tr -d "()#" | head -1)
     echo "  (see the dump above; export the rumble line if needed)"
   fi'
S 'echo "  gpio state now:"; cat /sys/kernel/debug/gpio 2>/dev/null | grep -iE "rumble|out |in " | head -8 | sed "s/^/     /"'
echo "=== done: tell me if it is still vibrating ==="
