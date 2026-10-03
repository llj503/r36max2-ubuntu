#!/bin/bash
# k72-btn-pinsel-compare.sh - compare the pinctrl group that puts the button pads
# into GPIO function: ours vs the vendor/rocknix dts for this exact device.  A
# pad missing from the group keeps whatever IOMUX the boot loader left on it, and
# then the GPIO input path never sees the key.
set -uo pipefail
OURS=/mnt/e/ubuntu/board/rk3326-xifan-r36max2.dts
THEIRS=/mnt/e/ubuntu/build/rocknix/dts/rk3326-xifan-r36max2.dts

for f in "$OURS" "$THEIRS"; do
  echo "=== $f ==="
  awk '/btn_pins_ctrl:/{flag=1} flag{print} flag&&/};/{exit}' "$f" | sed "s/^/  /"
done

echo
echo "=== every pin the joypad's 17 keys use, from each file ==="
for f in "$OURS" "$THEIRS"; do
  echo "  $f:"
  awk '/rocknix-singleadc-joypad \{/{j=1} j&&/gpios = <&gpio/{print} j&&/^\t\};/{exit}' "$f" |
    sed 's/^\s*//' | sort | uniq -c | sed 's/^/     /'
done

echo
echo "=== does the vendor DT put those four pads in GPIO function? ==="
awk '/btn_pins_ctrl:/{flag=1} flag{print} flag&&/};/{exit}' "$THEIRS" |
  grep -E "RK_PC[0-3]|RK_PC[4-7]" | sed 's/^/  theirs: /'
awk '/btn_pins_ctrl:/{flag=1} flag{print} flag&&/};/{exit}' "$OURS" |
  grep -E "RK_PC[0-3]|RK_PC[4-7]" | sed 's/^/  ours:   /'
