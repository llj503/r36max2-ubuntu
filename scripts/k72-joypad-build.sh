#!/bin/bash
# k72-joypad-build.sh - build the gpiod-converted joypad module against BOTH
# kernels; the point of the rewrite is that one source serves 6.12 and 7.2.
#
# Artifacts go to /mnt/e/ubuntu/artifacts/joypad (WSL /tmp gets reclaimed and
# previously swallowed the built .ko), each kernel's build log to logs/.
set -uo pipefail
W=/root/r36/k72joypad
A=/mnt/e/ubuntu/artifacts/joypad
L=/mnt/e/ubuntu/logs
X=ARCH=arm64
CROSS=CROSS_COMPILE=aarch64-linux-gnu-
mkdir -p "$A" "$L"

for K in /root/r36/linux-7.2.8 /root/r36/linux-6.12.79; do
  KV=$(cat "$K/include/config/kernel.release")
  echo "=== build against $KV ==="
  find "$W" \( -name '*.o' -o -name '*.ko' -o -name '*.mod*' -o -name '.*.cmd' \
       -o -name Module.symvers -o -name modules.order \) -delete
  make -C "$K" M="$W" $X $CROSS DEVICE=RK3326 modules > "$L/joypad-$KV.log" 2>&1
  rc=$?
  echo "  exit=$rc  errors=$(grep -c 'error:' "$L/joypad-$KV.log")  warnings=$(grep -c 'warning:' "$L/joypad-$KV.log")"
  grep -E "error:" "$L/joypad-$KV.log" | head -8 | sed 's/^/    /'
  grep -E "warning:.*(implicit|unused|incompatible)" "$L/joypad-$KV.log" | head -6 | sed 's/^/    W /'
  for f in "$W"/*.ko; do
    [ -e "$f" ] || continue
    b=$(basename "$f" .ko)
    cp -f "$f" "$A/$b-$KV.ko"
    echo "  staged $A/$b-$KV.ko ($(stat -c%s "$f") B, vermagic $(modinfo -F vermagic "$f" 2>/dev/null))"
  done
  echo "  unresolved symbols vs this kernel's Module.symvers:"
  for f in "$A"/*-$KV.ko; do
    [ -e "$f" ] || continue
    aarch64-linux-gnu-nm -u "$f" 2>/dev/null | awk '{print $2}' | sort -u > "$L/jneed.txt"
    awk '{print $2}' "$K/Module.symvers" | sort -u > "$L/jhave.txt"
    miss=$(comm -23 "$L/jneed.txt" "$L/jhave.txt" | tr '\n' ' ')
    echo "    $(basename "$f"): needs $(wc -l < "$L/jneed.txt"), unresolved: ${miss:-none}"
  done
done

echo "=== sha256 of what we will ship ==="
sha256sum "$A"/*.ko | sed "s|$A/||" | cut -c1-24,66- | sed 's/^/  /'
echo "=== joypad build done ==="
