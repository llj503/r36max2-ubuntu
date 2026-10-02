#!/bin/bash
K=/root/r36/linux-6.12.79
cd "$K"
echo "=== where does name_to_dev_t live, and does it handle UUID=/PARTUUID= ? ==="
grep -rln "name_to_dev_t" init/ block/ fs/ 2>/dev/null | head
grep -rn "PARTUUID\|devt_from_partuuid\|UUID=" init/do_mounts.c block/early.c 2>/dev/null | head -12
echo
echo "=== early_lookup_bdev path ==="
grep -n -A18 "^int __init early_lookup_bdev" init/do_mounts.c | head -30
echo
echo "=== initrd compression options currently set ==="
grep -nE "CONFIG_RD_|CONFIG_BLK_DEV_INITRD" .config
echo
echo "=== are these configurable (prompt) ? ==="
grep -n -A16 "^config BLK_DEV_INITRD" init/Kconfig | grep -E "^config|bool|depends" | head -8
grep -rn "config RD_GZIP" lib/Kconfig* init/Kconfig 2>/dev/null | head -3
