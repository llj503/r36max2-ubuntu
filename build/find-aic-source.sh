#!/bin/bash
# Find a driver source that supports the h_u02 revision (what our chip reports).
set -uo pipefail
echo "=== what is under /root/r36 ==="
du -sh /root/r36/* 2>/dev/null | sort -h | tail -15
echo "=== any aic8800 source trees around? ==="
find /root/r36 -maxdepth 4 -type d \( -iname '*aic*' -o -iname '*rocknix*' -o -iname '*arkos*' \) 2>/dev/null | head -20
echo "=== grep the clones for the h_u02 firmware name ==="
grep -rl 'fmacfw_patch_8800dc_h_u02' /root/r36 2>/dev/null | head -10
echo "=== grep for syscfg_tbl_masked (only newer drivers have it) ==="
grep -rl 'syscfg_tbl_masked' /root/r36 2>/dev/null | head -10
echo "=== our driver's own version/date ==="
grep -rnE 'DRIVER_VERSION|RELEASE DATE' /root/r36/wifi/aic8800dc-linux-patched-main/drivers/aic8800/aic8800_fdrv/rwnx_compat.h 2>/dev/null | head -5
grep -rn 'DRV_VERSION' /root/r36/wifi/aic8800dc-linux-patched-main/drivers/aic8800/aic8800_fdrv/*.h | head -5
echo "=== the vendor ko: its driver version + vermagic + git date ==="
modinfo /mnt/e/ubuntu/artifacts/wifi/aic8800_fdrv.ko | grep -E 'version|vermagic|srcversion'
strings -a /mnt/e/ubuntu/artifacts/wifi/aic8800_fdrv.ko | grep -E '^20[12][0-9]_[0-9]{4}|GIT|release' | head
