#!/bin/bash
# k72-rumble-off2.sh - the chips are exposed as gpiochip512..608 (32 lines each),
# so gpio0.B7 = local 15 = global 527.  Export exactly that and drive it low.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
S() { sshpass -p $PW ssh -o ConnectTimeout=15 root@$DEV "$@" </dev/null 2>/dev/null; }

S 'b=$(cat /sys/class/gpio/gpiochip512/base); echo "  gpio0 base=$b"
   n=$((b + 15))
   [ -e /sys/class/gpio/gpio$n ] || echo $n > /sys/class/gpio/export 2>&1 | sed "s/^/  export: /"
   if [ -e /sys/class/gpio/gpio$n/value ]; then
     echo out > /sys/class/gpio/gpio$n/direction
     echo 1 > /sys/class/gpio/gpio$n/value
     echo "  gpio$n = physical 1 (motor off if the enable is active-low)"
     sleep 1
     echo 0 > /sys/class/gpio/gpio$n/value
     echo "  gpio$n = physical 0 (motor off if the enable is active-high)"
   else
     echo "  export failed"
   fi
   mount -t debugfs none /sys/kernel/debug 2>/dev/null
   sed -n "/gpiochip0/,/gpiochip1/p" /sys/kernel/debug/gpio | sed "s/^/    /"
   echo "  joypad module: $(lsmod | grep -c joypad)"'
echo "=== I drove the line both ways 1 second apart; tell me whether it is silent now ==="
