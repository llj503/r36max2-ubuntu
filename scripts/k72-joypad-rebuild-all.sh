#!/bin/bash
# k72-joypad-rebuild-all.sh - after the gpiod polarity fixes: rebuild the board
# dtbs in both trees and the converted joypad module for both kernels, then
# verify from the compiled artifacts that the levels are what we intend.
set -uo pipefail
X=ARCH=arm64
CROSS=CROSS_COMPILE=aarch64-linux-gnu-
DTS=/mnt/e/ubuntu/projects/r36max2/dt/rk3326-xifan-r36max2.dts
LOG=/mnt/e/ubuntu/logs/k72-joypad-rebuild.log

echo "=== dtbs ==="
for K in /root/r36/linux-7.2.8 /root/r36/linux-6.12.79; do
  D=$K/arch/arm64/boot/dts/rockchip
  cp -f "$DTS" "$D/"
  make -C "$K" $X $CROSS dtbs > "$LOG-dtbs-$(basename "$K").log" 2>&1
  echo "  $(basename "$K"): exit=$? $(grep -ciE 'error' "$LOG-dtbs-$(basename "$K").log") errors"
  echo "    gpio flags in the compiled dtb:"
  dtc -I dtb -O dts "$D/rk3326-xifan-r36max2.dtb" 2>/dev/null |
    grep -E "amux-a-gpios|amux-b-gpios|amux-en-gpios|rumble-gpio" |
    sed 's/^/      /'
  echo "    sha $(sha256sum "$D/rk3326-xifan-r36max2.dtb" | cut -c1-16) size $(stat -c%s "$D/rk3326-xifan-r36max2.dtb")"
done

echo
echo "=== modules (this also re-runs the vermagic/unresolved-symbol audit) ==="
bash /mnt/e/ubuntu/scripts/k72-joypad-build.sh 2>&1 | tee "$LOG" | tail -30

echo
echo "=== prove the polarity-aware calls are in the object we ship ==="
K=/root/r36/linux-7.2.8
NM=$(command -v aarch64-linux-gnu-nm || echo nm)
$NM -u /root/r36/k72joypad/rocknix-singleadc-joypad.ko 2>/dev/null |
  grep -E "gpiod" | sed 's/^/  imported: /'

echo
echo "=== regenerated gpiod patch for the record ==="
P=/mnt/e/ubuntu/projects/r36max2/patches/joypad-gpiod.patch
rm -rf /tmp/jpd; mkdir -p /tmp/jpd/a /tmp/jpd/b
cp /root/r36/joypad/src/*.c /root/r36/joypad/src/*.h /tmp/jpd/a/ 2>/dev/null
cp /root/r36/k72joypad/*.c /root/r36/k72joypad/*.h /tmp/jpd/b/ 2>/dev/null
rm -f /tmp/jpd/b/*.mod.c
(cd /tmp/jpd && diff -ruN a b > /tmp/jp.patch 2>/dev/null; exit 0)
grep -vE "^Only in " /tmp/jp.patch > "$P"
echo "  $P: $(wc -l < "$P") lines"
grep -E "^\+\+\+ " "$P" | sed 's/^/    /'
echo "=== rebuild all done ==="
