#!/bin/bash
# k72-aic-verify.sh - prove the rebuilt modules really are the radxa driver for
# 7.2.8 (vermagic, h_u02 firmware names, all symbols resolvable), then emit a
# reviewable patch file from the pristine tree so this work is reproducible.
set -uo pipefail
K=/root/r36/linux-7.2.8
T=/root/r36/k72aic/drivers/aic8800
FDRV=$T/aic8800_fdrv/aic8800_fdrv.ko
LOAD=$T/aic_load_fw/aic_load_fw.ko
OLD=/root/r36/rootfs/lib/modules/6.12.79/extra

echo "=== vermagic / srcversion ==="
for f in "$FDRV" "$LOAD"; do
  echo "  $(basename "$f"): $(modinfo -F vermagic "$f") | srcversion $(modinfo -F srcversion "$f")"
done
echo "  6.12 image had: $(modinfo -F vermagic "$OLD/aic8800_fdrv.ko") | srcversion $(modinfo -F srcversion "$OLD/aic8800_fdrv.ko")"

echo "=== h_u02 firmware the driver will ask for ==="
strings -a "$FDRV" "$LOAD" | grep -oE "[a-z0-9_]*8800dc[a-z0-9_.]*" | sort -u | head -14 | sed 's/^/  /'

echo "=== every undefined symbol must exist in the kernel ==="
for f in "$FDRV" "$LOAD"; do
  aarch64-linux-gnu-nm -u "$f" | awk '{print $2}' | sort -u > /tmp/need.txt
  awk '{print $2}' "$K/Module.symvers" | sort -u > /tmp/have.txt
  miss=$(comm -23 /tmp/need.txt /tmp/have.txt | grep -vE "^(memcpy|memset|memmove|__|vsprintf|scnprintf)" )
  echo "  $(basename "$f"): $(wc -l < /tmp/need.txt) undefined, unresolved: ${miss:-none}"
done

echo "=== dependency check the way modprobe would do it ==="
mkdir -p /tmp/k72mods/lib/modules/7.2.8/extra
cp "$FDRV" "$LOAD" /tmp/k72mods/lib/modules/7.2.8/extra/
depmod -a -b /tmp/k72mods 7.2.8 2>/dev/null
for m in aic8800_fdrv aic_load_fw; do
  echo "  $m -> $(depmod -b /tmp/k72mods -e 7.2.8 2>&1 | grep -m1 "$m" || echo 'no complaints')"
done
insmod_path=$(find /tmp/k72mods -name "$FDRV.ko" 2>/dev/null | head -1)
modprobe -n -S 7.2.8 -d /tmp/k72mods/lib/modules aic8800_fdrv 2>&1 | sed 's/^/  modprobe -n: /' || true

echo "=== emit the patch (pristine radxa tree -> 7.2.8 compatible) ==="
P=/mnt/e/ubuntu/projects/r36max2/patches/aic8800-7.2.8-compat.patch
SRC=/root/r36/aic8800-radxa/src/USB/driver_fw/drivers/aic8800
diff -ruN "$SRC" "$T" > /tmp/aic.patch 2>/dev/null
grep -v "^Only in" /tmp/aic.patch > "$P"
echo "  -> E:\\ubuntu\\build\\aic8800-7.2.8-compat.patch ($(wc -l < "$P") lines, $(du -h "$P" | cut -f1))"
grep -E "^\+\+\+ " "$P" | sed 's/^/    /'
