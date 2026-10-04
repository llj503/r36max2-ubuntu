#!/bin/bash
# Does the AIC driver's requested firmware match what we shipped in /lib/firmware?
set -uo pipefail
A=/root/r36/wifi/aic8800dc-linux-patched-main
R=/root/r36/rootfs
echo "=== firmware names requested by the driver ==="
grep -rhoE '"[A-Za-z0-9_./-]*\.bin"' "$A/drivers/aic8800" 2>/dev/null | sort -u | head -40
echo "=== prefix/dir the driver builds them from ==="
grep -rnE 'FIRMWARE|\.fw|aic8800DC|sprintf.*firm' "$A/drivers/aic8800/aic8800_fdrv/aic8800_fdrv.h" 2>/dev/null | grep -iE 'firm|\.bin' | head -20
grep -rnE '#define.*(FW|CFG|CALIB).*PATH|aic_firmware|FIRMWARE_DIR' "$A/drivers/aic8800" 2>/dev/null | head -20
echo "=== what we shipped ==="
ls "$R/lib/firmware/" | head -20
echo "--- aic8800DC dir ---"
ls "$R/lib/firmware/aic8800DC/" 2>/dev/null
echo "=== the device's own firmware dir (extracted from EmuELEC, for comparison) ==="
tar tzf /mnt/e/ubuntu/artifacts/wifi/aic8800DC-firmware.tar.gz 2>/dev/null | head -40
echo "=== userconfig / powerlimit the driver reads ==="
grep -rnE 'aic_userconfig|aic_powerlimit' "$A/drivers/aic8800" 2>/dev/null | head -8
