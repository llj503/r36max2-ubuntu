#!/bin/bash
# k72-wait-up.sh - reboot the card into whatever is on boot.ini, wait for SSH,
# and prove from the booted device tree which GPIO polarity flags the kernel
# actually got (the only way to know the new dtb is really in use).
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
S() { sshpass -p $PW ssh -o ConnectTimeout=6 root@$DEV "$@" </dev/null 2>/dev/null; }

echo "[$(date +%H:%M:%S)] rebooting $DEV"
S '(sleep 1; reboot) >/dev/null 2>&1 &'
for i in $(seq 1 40); do
  sleep 5
  S 'true' && { echo "[$(date +%H:%M:%S)] ssh is back after ~$((i*5))s"; break; }
  # the lease can move; sweep the usual suspects
  for ip in 192.168.31.210 192.168.31.208 192.168.31.211; do
    if sshpass -p $PW ssh -o ConnectTimeout=4 root@$ip 'true' 2>/dev/null; then
      DEV=$ip; echo "[$(date +%H:%M:%S)] ssh back on $ip after ~$((i*5))s"; break 2
    fi
  done
done
S 'true' || { echo "[$(date +%H:%M:%S)] still not reachable after 200s"; exit 1; }

S 'echo "  kernel : $(uname -r)"
   echo "  uptime : $(cut -d" " -f1 /proc/uptime)s"
   echo "  boot.ini used it: FAT has $(ls /run/r36-boot/*.dtb 2>/dev/null | wc -l) dtbs (not mounted here)"
   J=/proc/device-tree/rocknix-singleadc-joypad
   echo "  joypad node in the FDT: $([ -d $J ] && echo present || echo MISSING)"
   for n in amux-a-gpios amux-b-gpios amux-en-gpios rumble-gpio; do
     if [ -e "$J/$n" ]; then
       echo "  $(printf "%-14s" $n) = $(od -An -tu4 -N12 $J/$n | tr -s " ")   (last: 0=ACTIVE_HIGH 1=ACTIVE_LOW)"
     else
       echo "  $n NOT FOUND - node children: $(ls $J 2>/dev/null | grep -i gpio | tr "\n" " ")"
     fi
   done
   mount -t debugfs none /sys/kernel/debug 2>/dev/null
   grep -iE "rumble|amux" /sys/kernel/debug/gpio 2>/dev/null | sed "s/^/  pin: /"
   echo "  module: $(lsmod | awk "/joypad/{print \$1\" refcount=\"\$3}")"
   echo "  module sha: $(sha256sum /lib/modules/$(uname -r)/extra/rocknix-singleadc-joypad.ko 2>/dev/null | cut -c1-16)"
   echo "  input: $(ls /dev/input/by-path/ 2>/dev/null | tr "\n" " ")"
   echo "  js: $(ls /dev/input/js* 2>/dev/null | tr "\n" " ")"
   dmesg | grep -aiE "joypad rumble|has gpio rumble|probe success|failed to get amux" | tail -4 | sed "s/^/  dmesg: /"'
echo "DEV=$DEV"
echo "=== wait-up done ==="
