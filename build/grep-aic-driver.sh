#!/bin/bash
# Why does the AIC firmware upload fail? Find the code paths behind the exact
# strings that appeared on the device: "unsupported id: 2", "bin upload fail".
set -uo pipefail
A=/root/r36/wifi/aic8800dc-linux-patched-main
echo "=== 'unsupported id' ==="
grep -rn "unsupported id" "$A" | head -5
echo "=== context around it ==="
f=$(grep -rl "unsupported id" "$A" | head -1); echo "file: $f"
ln=$(grep -n "unsupported id" "$f" | head -1 | cut -d: -f1)
[ -n "$ln" ] && sed -n "$((ln-40)),$((ln+10))p" "$f"
echo "=== 'bin upload fail' ==="
grep -rn "bin upload fail" "$A" | head -3
g=$(grep -rl "bin upload fail" "$A" | head -1)
ln2=$(grep -n "bin upload fail" "$g" | head -1 | cut -d: -f1)
[ -n "$ln2" ] && sed -n "$((ln2-45)),$((ln2+15))p" "$g"
echo "=== which chip ids does this driver know? ==="
grep -rnE 'CHIP_AIC88(00|01)[A-Z0-9_]*|tp_mode_flag|aic_chip_type' "$A/drivers/aic8800/aic8800_fdrv/rwnx_defs.h" 2>/dev/null | head -20
grep -rnE 'case 2|id == 2|chip_id' "$A/drivers/aic8800/aic_load_fw/aicwtx_mgr.c" 2>/dev/null | head -20
