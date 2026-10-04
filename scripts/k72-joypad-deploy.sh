#!/bin/bash
# k72-joypad-deploy.sh - emit the gpiod patch for the record, then install the
# 7.2.8 joypad modules onto the running card and load them live (no reboot: the
# device is already up on 7.2.8 with working WiFi).
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
SRC=/root/r36/joypad/src
NEW=/root/r36/k72joypad
S() { sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV "$@" </dev/null 2>/dev/null; }

echo "=== [1] patch file ==="
P=/mnt/e/ubuntu/projects/r36max2/patches/joypad-gpiod.patch
mkdir -p /tmp/jpd/a /tmp/jpd/b
rm -rf /tmp/jpd/a/* /tmp/jpd/b/*
cp "$SRC"/*.c "$SRC"/*.h /tmp/jpd/a/ 2>/dev/null
cp "$NEW"/*.c "$NEW"/*.h /tmp/jpd/b/ 2>/dev/null
(cd /tmp/jpd && diff -ruN a b > /tmp/jp.patch; exit 0)
grep -vE "^Only in " /tmp/jp.patch > "$P"
echo "  $P: $(wc -l < "$P") lines, $(du -h "$P" | cut -f1)"
grep -E "^\+\+\+ " "$P" | sed 's/^/    /'

echo "=== [2] which .ko are which kernel ==="
for f in "$NEW"/*.ko; do echo "  $(basename "$f"): $(modinfo -F vermagic "$f" 2>/dev/null)"; done

echo "=== [3] install the 7.2.8 ones on the running card ==="
S 'uname -r | sed "s/^/  device kernel: /"'
for f in "$NEW"/*.ko; do
  if modinfo -F vermagic "$f" 2>/dev/null | grep -q "^$(uname -r 2>/dev/null || echo 7.2.8)"; then :; fi
done
scp_out=$(sshpass -p $PW scp -q "$NEW/rocknix-singleadc-joypad.ko" "$NEW/rocknix-joypad.ko" \
          "root@$DEV:/lib/modules/7.2.8/extra/" 2>&1); echo "  scp: ${scp_out:-ok}"
S 'depmod -a 7.2.8
   ls -l /lib/modules/7.2.8/extra/ | sed "s/^/    /"
   echo "  removing any stale module first: $(lsmod | awk "/joypad/{print \$1}")"
   rmmod rocknix_singleadc_joypad 2>/dev/null
   modprobe rocknix_singleadc_joypad 2>&1 | sed "s/^/  modprobe: /"
   sleep 2
   echo "  loaded: $(lsmod | awk "/joypad|polldev/{print \$1\"=\"\$3}")"
   echo "  input devices now:"; ls -l /dev/input/by-path/ | sed "s/^/      /"
   echo "  event names:"; grep -E "^N: Name" /proc/bus/input/devices | sed "s/^/      /"
   echo "  js devices: $(ls /dev/input/js* 2>/dev/null | tr "\n" " ")"
   dmesg | tail -12 | sed "s/^/  dmesg: /"'
echo "=== deploy done ==="
