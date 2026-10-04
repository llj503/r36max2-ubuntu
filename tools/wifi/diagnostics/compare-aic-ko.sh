#!/bin/bash
# Compare the vendor's working AIC .ko (extracted from EmuELEC) with the one we built.
set -uo pipefail
A=/root/r36/wifi/aic8800dc-linux-patched-main
V=/mnt/e/ubuntu/artifacts/wifi
echo "=== vendor ko ==="
ls -la "$V"
modinfo "$V/aic8800_fdrv.ko" 2>/dev/null | grep -E '^(version|vermagic|name|filename|description)'
modinfo "$V/aic_load_fw.ko" 2>/dev/null | grep -E '^(version|vermagic|name)'
echo "=== our ko ==="
modinfo "$A/drivers/aic8800/aic8800_fdrv/aic8800_fdrv.ko" 2>/dev/null | grep -E '^(version|vermagic|name)'
echo "=== RELEASE DATE string in each (driver build) ==="
for k in "$V/aic8800_fdrv.ko" "$A/drivers/aic8800/aic8800_fdrv/aic8800_fdrv.ko"; do
  echo "-- $k"
  strings "$k" 2>/dev/null | grep -E 'RELEASE DATE|unsupported id|aic8800dc|8800dc_|GIT' | head -12
done
echo "=== firmware filenames referenced ==="
for k in "$V/aic_load_fw.ko" "$A/drivers/aic8800/aic_load_fw/aic_load_fw.ko"; do
  echo "-- $k"
  strings "$k" 2>/dev/null | grep -E '\.bin$|aic8800|fw_|lmac|fmac' | head -20
done
echo "=== module parameters available in each fdrv ==="
for k in "$V/aic8800_fdrv.ko" "$A/drivers/aic8800/aic8800_fdrv/aic8800_fdrv.ko"; do
  echo "-- $k"; modinfo -p "$k" 2>/dev/null
done
echo "=== does the vendor ko mention the same failing strings? ==="
strings "$V/aic8800_fdrv.ko" 2>/dev/null | grep -cE 'bin upload fail|patch_tbl upload fail' || true
echo "=== usb ids each driver claims ==="
strings "$V/aic8800_fdrv.ko" 2>/dev/null | grep -iE 'aic8800|a69c' | head
echo "=== source: what chooses between u02 / u02h / h_u02 firmware ==="
grep -rn "u02\|_h_\|chip_id\|aic_chip_id" "$A/drivers/aic8800/aic_load_fw/"*.c 2>/dev/null | grep -iE 'u02|chip' | head -20
