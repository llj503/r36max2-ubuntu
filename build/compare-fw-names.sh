#!/bin/bash
# Which firmware files does the WORKING vendor driver reference, vs our build?
set -uo pipefail
A=/root/r36/wifi/aic8800dc-linux-patched-main
V=/mnt/e/ubuntu/artifacts/wifi
S=$A/drivers/aic8800

echo "=== .bin names inside the vendor fdrv ko (this one works on this chip) ==="
strings -a "$V/aic8800_fdrv.ko" | grep -E '\.bin$|\.txt$' | sort -u
echo "=== .bin names inside the vendor aic_load_fw ko ==="
strings -a "$V/aic_load_fw.ko" | grep -E '\.bin$|\.txt$' | sort -u
echo "=== our fdrv ko ==="
strings -a "$S/aic8800_fdrv/aic8800_fdrv.ko" | grep -E '\.bin$|\.txt$' | sort -u
echo "=== our load_fw ko ==="
strings -a "$S/aic_load_fw/aic_load_fw.ko" | grep -E '\.bin$|\.txt$' | sort -u
echo "=== does our source already define the h_u02 / u02h names? ==="
grep -rnE 'define .*(8800DC).*(H_U02|U02H|_h_u02|_u02h)' "$S" --include=*.c --include=*.h | head -20
echo "=== all the RWNX_*_NAME* macros for 8800dc ==="
grep -rhoE 'RWNX_[A-Z_0-9]*NAME[0-9A-Z_]*_8800DC[A-Z_0-9]*' "$S" --include=*.c --include=*.h | sort -u
echo "=== where chip_sub_id==2 / CHIP_SUB_REV constants are used ==="
grep -rnE 'CHIP_SUB_REV_[A-Z0-9]+|chip_sub_id (==|<|>) [0-9]' "$S" --include=*.c --include=*.h | head -25
