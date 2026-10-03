#!/bin/bash
# k72-joypad-mkpatch.sh - regenerate build/joypad-gpiod.patch from the two
# source files only (no .mod.c build noise), with a/ b/ labels so `patch -p1`
# works, and then prove it: pristine tree + patch == the .ko we just built.
set -uo pipefail
SRC=/root/r36/joypad/src
NEW=/root/r36/k72joypad
P=/mnt/e/ubuntu/build/joypad-gpiod.patch
T=/tmp/jmk; rm -rf $T; mkdir -p $T/a $T/b $T/test

for f in rocknix-joypad.c rocknix-singleadc-joypad.c rocknix-joypad.h; do
  cp "$SRC/$f" "$T/a/$f"; cp "$NEW/$f" "$T/b/$f"
done

for f in rocknix-joypad.c rocknix-singleadc-joypad.c; do
  diff -u --label "a/$f" --label "b/$f" "$T/a/$f" "$T/b/$f"
done > "$P"
echo "  $P: $(wc -l < "$P") lines, $(grep -c '^@@' "$P") hunks"
grep -E '^(---|\+\+\+)' "$P" | sed 's/^/    /'

echo "=== does it apply to a pristine tree? ==="
cp "$T/a/"* "$T/test/"
for f in rocknix-joypad.c rocknix-singleadc-joypad.c rocknix-joypad.h; do
  cp -f "$SRC/$f" "$T/test/$f" 2>/dev/null
done
cp "$SRC/Makefile" "$T/test/" 2>/dev/null
(cd "$T/test" && patch -p1 --dry-run -s < "$P" && echo "  dry-run: clean" && patch -p1 -s < "$P" && echo "  applied") || { echo "  !! patch does NOT apply"; exit 1; }
for f in rocknix-joypad.c rocknix-singleadc-joypad.c; do
  if cmp -s "$T/test/$f" "$NEW/$f"; then echo "  $f identical after apply"; else echo "  !! $f differs after apply"; fi
done

echo "=== build the patched pristine copy for 7.2.8 and compare the .ko ==="
K=/root/r36/linux-7.2.8
make -C "$K" M="$T/test" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- DEVICE=RK3326 modules > /tmp/jmk-build.log 2>&1
echo "  exit=$? errors=$(grep -c 'error:' /tmp/jmk-build.log)"
for f in rocknix-singleadc-joypad rocknix-joypad; do
  A=$T/test/$f.ko; B=$NEW/$f.ko
  if [ -e "$A" ] && [ -e "$B" ]; then
    if cmp -s "$A" "$B"; then echo "  $f.ko byte-identical ($(stat -c%s "$A") B)"
    else echo "  $f.ko differs: $(stat -c%s "$A") vs $(stat -c%s "$B")  (srcversion: $(modinfo -F srcversion "$A") / $(modinfo -F srcversion "$B"))"; fi
  else echo "  $f.ko missing (A=$([ -e "$A" ] && echo y || echo n) B=$([ -e "$B" ] && echo y || echo n))"; fi
done

echo "=== stage the new dtbs as recovery artifacts ==="
cp -f /root/r36/linux-7.2.8/arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dtb \
      /mnt/e/ubuntu/artifacts/dtb/rk3326-xifan-r36max2-7.2.8-gpiodfix.dtb
cp -f /root/r36/linux-6.12.79/arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dtb \
      /mnt/e/ubuntu/artifacts/dtb/rk3326-xifan-r36max2-6.12-gpiodfix.dtb
sha256sum /mnt/e/ubuntu/artifacts/dtb/*gpiodfix* | cut -c1-24,60- | sed 's/^/  /'
echo "=== mkpatch done ==="
