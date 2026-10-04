#!/bin/bash
# Fix firmware staging: drop the stray file copied by an empty-variable cp, then
# merge the device's proven AIC8800DC firmware over the driver repo's copy.
set -u
FW=/root/r36/out/firmware/aic8800DC
SRC=/root/r36/devfw/aic8800DC

rm -f "$FW/init"
if [ -d "$SRC" ]; then
  cp -n "$SRC"/* "$FW"/ 2>/dev/null
  echo "merged device firmware from $SRC"
else
  echo "WARN: $SRC missing"
fi

echo "=== file count: $(ls "$FW" | wc -l) ==="
for f in fmacfw_calib_8800dc_h_u02.bin fmacfw_patch_8800dc_h_u02.bin \
         fmacfw_patch_tbl_8800dc_h_u02.bin fw_adid_8800dc_u02h.bin \
         fmacfw_8800dc_u02.bin fmacfw_calib_8800dc_u02.bin; do
  if [ -e "$FW/$f" ]; then echo "present  $f"; else echo "MISSING  $f"; fi
done
echo "=== no stray non-firmware files ==="
find "$FW" -type f ! -name "*.bin" ! -name "*.txt" -print
