#!/bin/bash
# k72-joypad-load.sh - the previous copy shipped the 6.12 .ko by mistake (the
# loop built 6.12 last).  Rebuild for 7.2.8 only, verify vermagic, install,
# load, and report the input devices.  Also regenerate the patch without the
# generated *.mod.c files.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
K=/root/r36/linux-7.2.8
NEW=/root/r36/k72joypad
S() { sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV "$@" </dev/null 2>/dev/null; }

echo "=== rebuild for 7.2.8 ==="
find "$NEW" \( -name '*.o' -o -name '*.ko' -o -name '*.mod*' -o -name '.*.cmd' \
     -o -name Module.symvers -o -name modules.order \) -delete
make -C "$K" M="$NEW" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- DEVICE=RK3326 modules 2>&1 | \
  grep -E "error|warning|\.ko" | tail -6
for f in "$NEW"/*.ko; do echo "  $(basename "$f"): $(modinfo -F vermagic "$f")"; done

echo "=== clean the patch (drop generated *.mod.c) ==="
rm -rf /tmp/jpd; mkdir -p /tmp/jpd/a /tmp/jpd/b
cp /root/r36/joypad/src/rocknix-joypad.c /root/r36/joypad/src/rocknix-singleadc-joypad.c \
   /root/r36/joypad/src/rocknix-joypad.h /tmp/jpd/a/
cp "$NEW"/rocknix-joypad.c "$NEW"/rocknix-singleadc-joypad.c "$NEW"/rocknix-joypad.h /tmp/jpd/b/
(cd /tmp/jpd && diff -ruN a b > /tmp/jp.patch)
grep -vE "^Only in " /tmp/jp.patch > /mnt/e/ubuntu/build/joypad-gpiod.patch
echo "  joypad-gpiod.patch: $(wc -l < /mnt/e/ubuntu/build/joypad-gpiod.patch) lines"
grep -E "^\+\+\+ " /mnt/e/ubuntu/build/joypad-gpiod.patch | sed 's/^/    /'

echo "=== install + load ==="
sshpass -p $PW scp -q "$NEW"/rocknix-singleadc-joypad.ko "$NEW"/rocknix-joypad.ko \
   "root@$DEV:/lib/modules/7.2.8/extra/" 2>/dev/null
S 'depmod -a 7.2.8
   modprobe rocknix_singleadc_joypad 2>&1 | sed "s/^/  modprobe: /"
   sleep 2
   echo "  loaded: $(lsmod | awk "/joypad|polldev/{print \$1\"=\"\$3}" | tr "\n" " ")"
   echo "  by-path:"; ls /dev/input/by-path/ | sed "s/^/      /"
   echo "  names:"; grep -E "^N: Name" /proc/bus/input/devices | sed "s/^/      /"
   echo "  js: $(ls /dev/input/js* 2>/dev/null | tr "\n" " ")"
   dmesg | grep -aiE "joypad|retrogame|gpiod|gpio" | tail -12 | sed "s/^/  dmesg: /"'
echo "=== load done ==="
