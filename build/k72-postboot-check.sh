#!/bin/bash
# k72-postboot-check.sh - the card is back on the network after the dtb change.
# Report exactly what the running kernel's device tree says about the four GPIOs
# the joypad driver owns, whether the module auto-loaded, and whether the motor
# is quiet - before we spend a capture window on events.
set -uo pipefail
PW=ubuntu
DEV=""
for i in $(seq 1 20); do
  for ip in 192.168.31.209 192.168.31.210 192.168.31.208; do
    sshpass -p $PW ssh -o ConnectTimeout=6 root@$ip 'echo ok' >/dev/null 2>&1 && { DEV=$ip; break; }
  done
  [ -n "$DEV" ] && break
  sleep 4
done
[ -n "$DEV" ] || { echo "not reachable after ~150s"; exit 1; }
echo "device: $DEV"
S() { sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV "$@" </dev/null 2>/dev/null; }

S 'echo "  kernel : $(uname -r)"
   echo "  uptime : $(cut -d" " -f1 /proc/uptime)s"
   echo "  wlan0  : $(ip -4 -br addr show wlan0 | awk "{print \$3}")"
   echo "  joypad : $(lsmod | awk "/joypad|polldev|input_poll/{print \$1\"=\"\$3}" | tr "\n" " ")"
   echo "  failed units: $(systemctl --failed --no-legend --plain | wc -l)"
   echo "=== the DT the kernel actually booted with ==="
   for n in amux-a-gpios amux-b-gpios amux-en-gpios rumble-gpio; do
     J=$(find /proc/device-tree -name "$n" 2>/dev/null | head -1)
     if [ -n "$J" ]; then
       printf "  %-14s raw=%s\n" "$n" "$(od -An -tu4 -N4 "$J" | tr -d " " | tr "\n" " ")"
     else
       echo "  $n NOT IN THE FLATTENED TREE"
     fi
   done
   echo "  (last number of each phandle triple = flags: 0 = ACTIVE_HIGH, 1 = ACTIVE_LOW)"
   echo "=== what the driver said at probe ==="
   dmesg | grep -iE "joypad|rocknix|rumble|polldev" | tail -14 | sed "s/^/  /"
   echo "=== the rumble pin as gpiod sees it ==="
   mount -t debugfs none /sys/kernel/debug 2>/dev/null
   grep -iE "rumble|amux|gpio-527|gpio-15 " /sys/kernel/debug/gpio 2>/dev/null | sed "s/^/  /"
   echo "=== input devices ==="
   ls -l /dev/input/by-path/ 2>/dev/null | sed "s/^/      /"
   echo "  js: $(ls /dev/input/js* 2>/dev/null | tr "\n" " ")"
   echo "=== is the motor being driven right now? ==="
   for g in $(ls /sys/kernel/debug/gpio 2>/dev/null); do :; done
   cat /sys/kernel/debug/gpio 2>/dev/null | awk "/gpio-527|rumble/{print \"  pin line: \" \$0}"
   echo "=== modules-load.d / journal for the module ==="
   cat /etc/modules-load.d/r36max2.conf 2>/dev/null | tr "\n" " "; echo
   journalctl -b -u systemd-modules-load.service --no-pager 2>/dev/null | tail -6 | sed "s/^/  /"'
echo "=== postboot check done ==="
