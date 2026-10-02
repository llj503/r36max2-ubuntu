#!/bin/bash
set -uo pipefail
A=/root/r36/wifi/aic8800dc-linux-patched-main
C=$A/drivers/aic8800/aic8800_fdrv/aicwf_compat_8800dc.c
echo "=== the chip_sub_id switch (around line 1980) ==="
sed -n '1930,2010p' "$C"
echo "=== all sub_id values handled anywhere ==="
grep -nE 'chip_sub_id|sub_id' "$C" | head -30
echo "=== where does chip_sub_id come from? ==="
grep -rnE 'chip_sub_id' "$A/drivers/aic8800/" --include=*.c --include=*.h | grep -v 'aicwf_compat_8800dc.c' | head -20
