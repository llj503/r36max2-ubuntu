#!/bin/bash
# k72-aic-build.sh - apply the compat patch (idempotent) and rebuild the driver
# against 7.2.8, reporting what is left.
set -uo pipefail
K=/root/r36/linux-7.2.8
T=/root/r36/k72aic/drivers/aic8800
X=ARCH=arm64
CROSS=CROSS_COMPILE=aarch64-linux-gnu-

python3 /mnt/e/ubuntu/scripts/k72-aic-compat.py 2>&1 | sed 's/^/  /'

echo "=== rebuild ==="
cd "$T" || exit 1
make -C "$T" KDIR="$K" $X $CROSS > /tmp/aic72b.log 2>&1
echo "  errors now: $(grep -c 'error:' /tmp/aic72b.log)"
grep -E "error:" /tmp/aic72b.log | sed -E 's/^/    /' | cut -c1-170 | sort -u | head -25
echo "=== produced ==="
find /root/r36/k72aic -name "*.ko" -printf "  %p  %s bytes\n"
cp /tmp/aic72b.log /mnt/e/ubuntu/logs/aic72-errors2.log
echo "  full log -> E:\\ubuntu\\logs\\aic72-errors2.log"
