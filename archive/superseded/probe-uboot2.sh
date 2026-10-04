#!/bin/bash
# Deeper probe: which script names / prefixes / filesystem paths does the device's u-boot scan for?
F=/mnt/e/ubuntu/artifacts/uboot.img
echo "=== boot_prefixes / boot_scripts / scriptfile ==="
strings -a "$F" | grep -E "boot_prefixes|boot_scripts|scriptfile|boot\.scr|boot\.cmd|boot\.ini|extlinux|KERNEL|Image|\.dtb|rkkn|bootcmd_mmc" | sort -u | head -30
echo
echo "=== full bootcmd_* lines ==="
strings -a "$F" | grep -E "^bootcmd_|^scan_dev_for|^distro_bootcmd|^boot_targets|^find_uuid|^get_usb_boot_mmcpart" | sort -u | head -25
echo
echo "=== ArkOS u-boot: what does it scan for ==="
strings -a /mnt/e/ubuntu/artifacts/arkos/uboot.img | grep -E "boot\.ini|dtb_name|Image|uInitrd|hwrev|sysboot|scan|fat" | sort -u | head -25
