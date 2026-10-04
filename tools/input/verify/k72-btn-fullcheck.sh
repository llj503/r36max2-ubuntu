#!/bin/bash
# k72-btn-fullcheck.sh - the button descriptors look unclaimed, but the poll loop
# runs (the axes report).  Decide with data: full gpio dump, the exact error
# count from the poll loop, and what gpiod returns for a NULL desc in 7.2.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
S() { sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV "$@" </dev/null 2>/dev/null; }

echo "=== A. the whole /sys/kernel/debug/gpio ==="
S 'mount -t debugfs none /sys/kernel/debug 2>/dev/null; cat /sys/kernel/debug/gpio'

echo
echo "=== B. is the poll loop complaining? ==="
S 'echo "  dev_err hits so far: $(dmesg | grep -ac "failed to get gpio state")"
   echo "  last dmesg lines: "; dmesg | tail -3 | sed "s/^/    /"'

echo
echo "=== C. keep the input device open for 4s and watch dmesg grow ==="
S 'before=$(dmesg | wc -l)
   ( timeout 4 dd if=/dev/input/event2 bs=64 count=1 of=/dev/null 2>/dev/null & )
   sleep 5
   after=$(dmesg | wc -l)
   echo "  dmesg lines: $before -> $after (delta $((after-before)))"
   dmesg | tail -4 | sed "s/^/    /"'

echo
echo "=== D. what does the 7.2.8 gpiod core return for a NULL descriptor ==="
S 'true'
grep -n -A14 "^static int __gpiod_get_value" /root/r36/linux-7.2.8/drivers/gpio/gpiod.c | head -22
echo "--- the consumer wrapper ---"
grep -n -B3 -A10 "int gpiod_get_value_cansleep" /root/r36/linux-7.2.8/drivers/gpio/gpiod.c | head -24

echo
echo "=== E. how does input_open_device reach our ->open? (enable flag) ==="
grep -n -E "joypad->enable" /root/r36/k72joypad/rocknix-singleadc-joypad.c | sed "s/^/  /"
echo "=== fullcheck done ==="
