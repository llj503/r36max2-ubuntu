#!/bin/bash
# k72-aic-trimpatch.sh - the generated patch still carried .o.d dependency
# files. Keep only the hunks for .c/.h sources, then re-prove that the trimmed
# patch alone builds the same byte-identical module.
set -uo pipefail
K=/root/r36/linux-7.2.8
SRC=/root/r36/aic8800-radxa/src/USB/driver_fw/drivers/aic8800
P=/mnt/e/ubuntu/build/aic8800-7.2.8-compat.patch

python3 - "$P" <<'PY'
import re, sys
p = sys.argv[1]
text = open(p, encoding="utf-8", errors="replace").read()
parts = re.split(r"(?m)^(?=diff -ruN )", text)
keep = []
for blk in parts:
    if not blk.strip():
        continue
    m = re.search(r"^\+\+\+ b/(\S+)", blk, re.M)
    name = m.group(1) if m else ""
    if re.search(r"\.(c|h)$", name):
        keep.append(blk if blk.endswith("\n") else blk + "\n")
open(p, "w", encoding="utf-8").write("".join(keep))
print("kept %d file block(s)" % len(keep))
PY

echo "=== trimmed patch: $(wc -l < "$P") lines, $(du -h "$P" | cut -f1) ==="
grep -E "^\+\+\+ " "$P" | sed 's/^/  /'

echo "=== re-prove: pristine + trimmed patch -> build ==="
rm -rf /tmp/aicprove2; mkdir -p /tmp/aicprove2/drivers
cp -r "$SRC" /tmp/aicprove2/drivers/aic8800
cd /tmp/aicprove2/drivers && patch -p1 -s -i "$P" && echo "  applied cleanly"
make -C /tmp/aicprove2/drivers/aic8800 KDIR="$K" ARCH=arm64 \
     CROSS_COMPILE=aarch64-linux-gnu- modules > /tmp/prove2.log 2>&1
echo "  errors: $(grep -c 'error:' /tmp/prove2.log)"
A=/tmp/aicprove2/drivers/aic8800/aic8800_fdrv/aic8800_fdrv.ko
B=/root/r36/k72aic/drivers/aic8800/aic8800_fdrv/aic8800_fdrv.ko
echo "  built: $(stat -c %s "$A" 2>/dev/null) bytes vs on-card $(stat -c %s "$B") bytes"
cmp -s "$A" "$B" && echo "  byte-identical: YES" || echo "  byte-identical: no"
