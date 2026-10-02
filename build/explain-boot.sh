#!/bin/bash
# Explain the three boot messages from the photo against the actual 6.12.79 source.
K=/root/r36/linux-6.12.79
cd "$K"

echo "=== 1) 'Disabling rootwait; root= is invalid.' — where and why ==="
grep -rn "Disabling rootwait" init/ | head -3
grep -n -B12 "Disabling rootwait" init/do_mounts.c | sed -n '1,30p'

echo
echo "=== does the kernel resolve root=UUID=<filesystem uuid>, or only partition uuid? ==="
grep -n "UUID=\|PARTUUID=\|devt_from_partuuid\|devt_from_devname" init/do_mounts.c | head -12
echo "--- msdos (MBR) disk-id + '-NN' support? ---"
grep -n "MSDOS_SUPER_MAGIC\|msdos\|disk identifier\|part_to_int" fs/partitions/msdos.c init/do_mounts.c 2>/dev/null | head -8

echo
echo "=== 2) 'compression method gzip not configured' — our initrd config ==="
grep -E "^(CONFIG_RD_GZIP|CONFIG_RD_LZ4|CONFIG_RD_LZMA|CONFIG_RD_XZ|CONFIG_RD_ZSTD|CONFIG_BLK_DEV_INITRD|CONFIG_INITRAMFS_SOURCE)=" .config

echo
echo "=== 3) panel-generic-dsi: what makes it fail to get display timing ==="
grep -n "Failed to request panel display timing" -B14 drivers/gpu/drm/panel/panel-generic-dsi.c 2>/dev/null | head -34
