#!/bin/bash
# k72-aic-mkpatch.sh - regenerate the AIC compat patch with RELATIVE paths and
# then prove it: apply it to a pristine copy of the radxa tree and build that
# copy against 7.2.8 from scratch.  If this passes, the patch file alone is
# enough for anyone to reproduce the port.
set -uo pipefail
K=/root/r36/linux-7.2.8
SRC=/root/r36/aic8800-radxa/src/USB/driver_fw/drivers/aic8800
NEW=/root/r36/k72aic/drivers/aic8800
D=/tmp/aicdiff
OUT=/mnt/e/ubuntu/projects/r36max2/patches/aic8800-7.2.8-compat.patch

EXCL=(--exclude='*.o' --exclude='*.o.d' --exclude='.*.cmd' --exclude='*.ko'
      --exclude='*.mod' --exclude='*.mod.c' --exclude='*.mod.o' --exclude='*.bak'
      --exclude='Module.symvers' --exclude='modules.order' --exclude='.tmp_*')

rm -rf "$D"; mkdir -p "$D/a" "$D/b"
cp -r "$SRC" "$D/a/aic8800"
cp -r "$NEW" "$D/b/aic8800"
# strip build artifacts from both sides so the diff is source-only
find "$D" \( -name '*.o' -o -name '.*.cmd' -o -name '*.ko' -o -name '*.mod' \
    -o -name '*.mod.c' -o -name '*.bak' -o -name 'Module.symvers' \
    -o -name 'modules.order' \) -delete

cd "$D" && diff -ruN a b > /tmp/p.patch
grep -vE "^Only in " /tmp/p.patch > "$OUT"
echo "=== $OUT: $(wc -l < "$OUT") lines, $(du -h "$OUT" | cut -f1) ==="
grep -E "^(---|\+\+\+) " "$OUT" | sed 's/^/  /'

echo "=== prove it: pristine tree + patch only ==="
rm -rf /tmp/aicprove; mkdir -p /tmp/aicprove/drivers
cp -r "$SRC" /tmp/aicprove/drivers/aic8800
cd /tmp/aicprove/drivers && patch -p1 -s -i "$OUT" && echo "  patch applied cleanly"
make -C /tmp/aicprove/drivers/aic8800 KDIR="$K" ARCH=arm64 \
     CROSS_COMPILE=aarch64-linux-gnu- modules > /tmp/prove.log 2>&1
echo "  errors: $(grep -c 'error:' /tmp/prove.log)"
grep -E "error:" /tmp/prove.log | head -5 | sed 's/^/    /'
find /tmp/aicprove -name "*.ko" -printf "  %p  %s bytes\n"
echo "=== compare with the tree we tested on hardware ==="
echo "  proven build : $(stat -c %s /tmp/aicprove/drivers/aic8800/aic8800_fdrv/aic8800_fdrv.ko 2>/dev/null) bytes"
echo "  on-card build: $(stat -c %s "$NEW/aic8800_fdrv/aic8800_fdrv.ko" 2>/dev/null) bytes"
echo "  identical: $(cmp -s /tmp/aicprove/drivers/aic8800/aic8800_fdrv/aic8800_fdrv.ko "$NEW/aic8800_fdrv/aic8800_fdrv.ko" && echo YES || echo 'no (timestamps/paths differ)')"
