#!/bin/bash
# Copy the patched compat file back into the build tree, rebuild aic8800_fdrv,
# and prove the h_u02 branches are really in the .ko.
set -eu
K=/root/r36/linux-6.12.79
A=/root/r36/wifi/aic8800dc-linux-patched-main/drivers/aic8800
E=/mnt/e/ubuntu/build/aic-src

cp -f "$E/aic8800_fdrv/aicwf_compat_8800dc.c" "$A/aic8800_fdrv/aicwf_compat_8800dc.c"
grep -n 'H_U02' "$A/aic8800_fdrv/aicwf_compat_8800dc.c"

echo "=== rebuild ==="
make -C "$A" KDIR="$K" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- 2>&1 | grep -E 'warning|error|Error|LD|Building|\.ko' | tail -12

echo "=== firmware names now referenced by our fdrv ==="
strings -a "$A/aic8800_fdrv/aic8800_fdrv.ko" | grep -E '\.bin$' | sort
echo "=== vs the working vendor ko ==="
strings -a /mnt/e/ubuntu/artifacts/wifi/aic8800_fdrv.ko | grep -E '^fmacfw.*\.bin$' | sort
echo "=== vermagic ==="
modinfo -F vermagic "$A/aic8800_fdrv/aic8800_fdrv.ko"
ls -la "$A/aic8800_fdrv/aic8800_fdrv.ko"
