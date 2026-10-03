#!/bin/bash
# k72-rumble-off.sh - the driver is unloaded but the pin is probably still being
# driven HIGH, and the evidence says the motor is active-HIGH in hardware (the DT
# claims ACTIVE_LOW).  Drive the line low through sysfs to make it stop.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
S() { sshpass -p $PW ssh -o ConnectTimeout=15 root@$DEV "$@" </dev/null 2>/dev/null; }

echo "=== gpio chips and their bases ==="
S 'for c in /sys/class/gpio/gpiochip*; do [ -d "$c" ] || continue; echo "  $(basename $c): base=$(cat $c/base) ngpio=$(cat $c/ngpio) label=$(cat $c/label 2>/dev/null)"; done'
S 'mount -t debugfs none /sys/kernel/debug 2>/dev/null; grep -n "gpio" /sys/kernel/debug/gpio 2>/dev/null | head -8 | sed "s/^/  dbg: /"'

echo "=== find the chip that owns the rumble line (gpio0, pin 15) ==="
S 'BASE=""
   for c in /sys/class/gpio/gpiochip*; do
     [ -d "$c" ] || continue
     L=$(cat "$c/label" 2>/dev/null)
     case "$L" in
       *ff110000*|*gpio0*) BASE=$(cat "$c/base"); echo "  matched $c label=$L base=$BASE";;
     esac
   done
   [ -n "$BASE" ] || { echo "  no explicit gpio0 label; trying each chip"; }
   echo "  chips present: $(ls -d /sys/class/gpio/gpiochip* 2>/dev/null | wc -l)"'

echo "=== drive ONLY the identified chip's line 15 low ==="
S 'b=$(cat /sys/class/gpio/gpiochip0/base 2>/dev/null)
   lbl=$(cat /sys/class/gpio/gpiochip0/label 2>/dev/null)
   echo "  gpiochip0: base=$b label=$lbl"
   if [ -n "$b" ]; then
     n=$((b + 15))
     [ -e /sys/class/gpio/gpio$n ] || echo $n > /sys/class/gpio/export 2>/dev/null
     if [ -e /sys/class/gpio/gpio$n/direction ]; then
       echo out > /sys/class/gpio/gpio$n/direction 2>/dev/null
       echo 0 > /sys/class/gpio/gpio$n/value 2>/dev/null
       echo "  gpio$n (gpio0.B7, the rumble pin) forced to physical 0; reads $(cat /sys/class/gpio/gpio$n/value)"
     else
       echo "  could not export gpio$n - is the driver still holding it? (lsmod: $(lsmod | grep -c joypad))"
     fi
   fi'
echo "=== done: the motor should be silent; tell me if it is not ==="
