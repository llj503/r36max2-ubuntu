#!/bin/bash
# k72-rumble-off3.sh - leave the rumble pin driven LOW (that is the "off" level
# if the motor enable is active-high, which is what the evidence suggests) and
# report the state so we can confirm.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
S() { sshpass -p $PW ssh -o ConnectTimeout=15 root@$DEV "$@" </dev/null 2>/dev/null; }

S 'b=$(cat /sys/class/gpio/gpiochip512/base); n=$((b + 15))
   echo "  gpio0.B7 -> global gpio$n"
   [ -e /sys/class/gpio/gpio$n ] || echo $n > /sys/class/gpio/export 2>&1 | sed "s/^/  export: /"
   if [ -e /sys/class/gpio/gpio$n/value ]; then
     echo out > /sys/class/gpio/gpio$n/direction 2>&1 | sed "s/^/  dir: /"
     echo 0 > /sys/class/gpio/gpio$n/value
     sync
     echo "  now driving gpio$n = 0 (was held high by the driver before unload)"
     echo "  value reads: $(cat /sys/class/gpio/gpio$n/value)"
   else
     echo "  export failed - the line may still be claimed by a driver"
   fi
   mount -t debugfs none /sys/kernel/debug 2>/dev/null
   sed -n "/gpiochip0/,/gpiochip1/p" /sys/kernel/debug/gpio | sed "s/^/    /"
   echo "  joypad module loaded: $(lsmod | grep -c joypad)"'
echo "=== tell me: is it silent now? ==="
