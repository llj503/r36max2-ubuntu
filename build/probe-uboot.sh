#!/bin/bash
# What boot-script magic does each u-boot build actually look for?
for f in /mnt/e/ubuntu/artifacts/uboot.img /mnt/e/ubuntu/artifacts/arkos/uboot.img; do
  echo "########## $f"
  strings -a "$f" | grep -iE "uboot-config|boot\.ini|extlinux|distro_bootcmd|boot_targets|sysboot|rockchip_boot|BOOT_DEVICE|devtype" | sort -u | head -20
  echo "--- version ---"
  strings -a "$f" | grep -oE "U-Boot 20[0-9]{2}\.[0-9]{2}[^ ]*" | sort -u | head -3
done
