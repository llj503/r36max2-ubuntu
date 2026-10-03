#!/bin/bash
# k72-joypad-reload.sh - install the con_id-fixed module and swap it in without a
# reboot (the fix is entirely module-side; the dtb is already the good one).
# Then prove the descriptors really got claimed: the 17 button labels must show
# up in /sys/kernel/debug/gpio, which is exactly what was missing before.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
KO=/mnt/e/ubuntu/artifacts/joypad/rocknix-singleadc-joypad-7.2.8.ko
S() { sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV "$@" </dev/null 2>/dev/null; }

echo "=== local module: $(sha256sum "$KO" | cut -c1-16) $(stat -c%s "$KO") B ==="
sshpass -p $PW ssh root@$DEV 'cat > /lib/modules/7.2.8/extra/rocknix-singleadc-joypad.ko' < "$KO"
S 'echo "  on card : $(sha256sum /lib/modules/7.2.8/extra/rocknix-singleadc-joypad.ko | cut -c1-16)"
   pkill -x evtest 2>/dev/null; pkill -x jstest 2>/dev/null; sleep 1
   echo "  refcount before rmmod: $(cat /sys/module/rocknix_singleadc_joypad/refcnt 2>/dev/null)"
   rmmod rocknix_singleadc_joypad 2>&1 | sed "s/^/  rmmod: /"
   echo "  loaded after rmmod: $(lsmod | grep -c rocknix)"
   modprobe rocknix_singleadc_joypad 2>&1 | sed "s/^/  modprobe: /"
   sleep 2
   echo "  loaded now: $(lsmod | awk "/joypad/{print \$1\" refcnt=\"\$3}")"
   mount -t debugfs none /sys/kernel/debug 2>/dev/null
   echo "  button consumers found: $(grep -cE "DPAD|BTN_" /sys/kernel/debug/gpio)"
   grep -E "DPAD|BTN_" /sys/kernel/debug/gpio | sed "s/^/    /"
   echo "  rumble/mux lines:"
   grep -iE "rumble|amux" /sys/kernel/debug/gpio | sed "s/^/    /"
   echo "  errors: $(dmesg | grep -ac "failed to get gpio state") failed-reads, $(dmesg | grep -ac "Failed to get gpio") acquire-failures"
   dmesg | tail -5 | sed "s/^/  dmesg: /"'
echo "=== reload done ==="
