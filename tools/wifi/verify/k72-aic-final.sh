#!/bin/bash
# k72-aic-final.sh - link the modules (default target only compiled objects),
# then sanity-check that what we produced is the SAME driver as the one the
# working 6.12 image ships, just rebuilt for 7.2.8.
set -uo pipefail
K=/root/r36/linux-7.2.8
T=/root/r36/k72aic/drivers/aic8800
cd "$T" || exit 1

make -C "$T" KDIR="$K" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- modules 2>&1 | \
  grep -E "error|\.ko|LD \[M\]|MODPOST|sign|prepare" | tail -12

echo "=== produced ==="
find /root/r36/k72aic -name "*.ko" -printf "  %p  %s bytes\n"

NEW=$(find /root/r36/k72aic -name aic8800_fdrv.ko | head -1)
OLD=/root/r36/rootfs/lib/modules/6.12.79/extra/aic8800_fdrv.ko
echo "=== same driver? compare against the 6.12 build ==="
echo "  old fdrv : $(stat -c %s "$OLD" 2>/dev/null) bytes"
echo "  new fdrv : $(stat -c %s "$NEW" 2>/dev/null) bytes"
echo "  old funcs: $(aarch64-linux-gnu-nm "$OLD" 2>/dev/null | grep -c ' t ')   new funcs: $(aarch64-linux-gnu-nm "$NEW" 2>/dev/null | grep -c ' t ')"
echo "  vermagic old: $(modinfo -F vermagic "$OLD" 2>/dev/null)"
echo "  vermagic new: $(modinfo -F vermagic "$NEW" 2>/dev/null)"
echo "  firmware names referenced (h_u02 must be there):"
strings -a "$NEW" 2>/dev/null | grep -E "fmacfw_(patch|calib)_8800dc" | sort -u | head -8 | sed 's/^/      /'
echo "  unresolved symbols the kernel must provide:"
aarch64-linux-gnu-nm -u "$NEW" 2>/dev/null | awk '{print $2}' | sort -u > /tmp/need.txt
awk '{print $2}' "$K/Module.symvers" | sort -u > /tmp/have.txt
miss=$(comm -23 /tmp/need.txt /tmp/have.txt | grep -vE "^(__|__cfi|_cond_resched|memcpy|memset|memmove)" | head -10)
echo "      missing: ${miss:-none}"
