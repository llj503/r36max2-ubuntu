#!/bin/bash
# Does the NEW aic_load_fw ask for anything the card doesn't have? And do our
# h_u02 blobs match the ones ArkOS/Rocknix ship for this board?
set -uo pipefail
W=/root/r36/aic8800-radxa/src/USB/driver_fw
R=/root/r36/rootfs
echo "=== firmware names referenced by the new aic_load_fw.ko ==="
names=$(strings -a "$W/drivers/aic8800/aic_load_fw/aic_load_fw.ko" | grep -E '^[a-zA-Z0-9_]+\.(bin|txt)$' | sort -u)
echo "$names"
echo "=== which of those are missing from the card? (only 8800dc/u02h matter for us) ==="
for f in $names; do
  if [ -f "$R/lib/firmware/$f" ] || [ -f "$R/lib/firmware/aic8800DC/$f" ]; then :; else echo "  not on card: $f  (in bundle: $([ -f "$W/fw/aic8800DC/$f" ] && echo yes || echo no))"; fi
done
echo "=== also the fdrv list ==="
for f in $(strings -a "$W/drivers/aic8800/aic8800_fdrv/aic8800_fdrv.ko" | grep -E '^fmacfw_8800dc|^fmacfw_(patch|calib|init|gaintbl|cinit).*8800dc|^aic_.*8800dc'); do
  [ -f "$R/lib/firmware/aic8800DC/$f" ] && echo "  ok      $f" || echo "  MISSING $f (bundle: $([ -f "$W/fw/aic8800DC/$f" ] && echo yes || echo no))"
done
echo "=== do our blobs match the bundle's? ==="
for f in fmacfw_patch_8800dc_h_u02.bin fmacfw_patch_tbl_8800dc_h_u02.bin fmacfw_calib_8800dc_h_u02.bin aic_userconfig_8800dc.txt; do
  a=$(md5sum "$R/lib/firmware/aic8800DC/$f" 2>/dev/null | cut -c1-12)
  b=$(md5sum "$W/fw/aic8800DC/$f" 2>/dev/null | cut -c1-12)
  echo "  $f  card=$a bundle=$b  $([ "$a" = "$b" ] && echo SAME || echo DIFFERENT)"
done
echo "=== what the bundle's aic8800DC dir holds ==="
ls "$W/fw/aic8800DC/" | head -30
echo "=== sizes of the lmac-side files on the card ==="
ls -la "$R/lib/firmware/aic8800DC/" | grep -E 'fw_(patch|adid)' | head
