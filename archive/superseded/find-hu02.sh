#!/bin/bash
# Look for a driver source that already knows the H_U02 chip revision.
set -uo pipefail
echo "=== our tree: any h_u02 / u02h references at all? ==="
grep -rniE 'h_u02|u02h' /root/r36/wifi/aic8800dc-linux-patched-main --include=*.c --include=*.h | head -20
echo "=== CHIP_SUB_REV / CHIP_REV constants ==="
grep -rnE 'CHIP_REV_[A-Z0-9]+ +[0-9]|CHIP_SUB_REV_[A-Z0-9]+ +[0-9]|#define CHIP_' /root/r36/wifi/aic8800dc-linux-patched-main/drivers/aic8800 | head -20
echo "=== rocknix clone: aic driver sources/patches? ==="
find /root/r36/rocknix -iname '*aic*' | head -20
grep -rl 'h_u02' /root/r36/rocknix 2>/dev/null | head -10
echo "=== full list of firmware names the VENDOR ko uses (this is the spec to match) ==="
strings -a /mnt/e/ubuntu/artifacts/wifi/aic8800_fdrv.ko | grep -E '^[a-zA-Z0-9_]+\.(bin|txt)$' | sort -u
echo "--- vendor aic_load_fw"
strings -a /mnt/e/ubuntu/artifacts/wifi/aic_load_fw.ko | grep -E '^[a-zA-Z0-9_]+\.(bin|txt)$' | sort -u
echo "=== our source: the macro definitions for those names ==="
grep -rnE '#define +(RWNX_[A-Z_0-9]+|.*NAME.*) +' /root/r36/wifi/aic8800dc-linux-patched-main/drivers/aic8800/aic8800_fdrv/aicwf_compat_8800dc.c | head -30
echo "=== what firmware files do we actually ship? ==="
ls /root/r36/rootfs/lib/firmware/aic8800DC/ | sort
