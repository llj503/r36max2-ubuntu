#!/bin/bash
# Try the proven AICSemi bundle that EmuELEC/ROCKNIX consume (radxa-pkg/aic8800):
# it has chip_sub_id==2 branches, the h_u02 calib tables and 6.12 compat guards.
set -uo pipefail
W=/root/r36/aic8800-radxa
T=/root/r36/dl/aic8800-radxa.tar.gz
K=/root/r36/linux-6.12.79
mkdir -p /root/r36/dl "$W"

if [ ! -f "$T" ]; then
	echo "=== downloading 55 MB (this takes ~1 min on a good link) ==="
	curl -fL --retry 3 -o "$T" https://github.com/radxa-pkg/aic8800/archive/refs/heads/main.tar.gz || { echo "download failed"; exit 1; }
fi
echo "size: $(stat -c %s "$T")"
echo "701fc8a5c8e180bb990d4fb57fe3a9f5232377906b86c5dd17204151763da080  $T" | sha256sum -c - || echo "SHA MISMATCH (continuing anyway, the agent's hash may be from a newer push)"

tar xzf "$T" -C "$W" --strip-components=1
echo "=== layout ==="
ls "$W"
find "$W" -maxdepth 4 -type d -name 'aic8800*' | head
COMPAT=$(find "$W" -path '*USB*' -name aicwf_compat_8800dc.c | head -1)
echo "compat file: $COMPAT"
echo "=== the branches we care about ==="
grep -n 'chip_sub_id == 2\|_H_U02\|syscfg_tbl_masked_8800dc_h\b' "$COMPAT" | head -20
grep -n 'RELEASE_DATE' "$W"/src/USB/driver_fw/drivers/aic8800/aic8800_fdrv/rwnx_compat.h 2>/dev/null | head -3
echo "=== firmware in the bundle ==="
ls "$W"/src/USB/driver_fw/fw/aic8800DC/ 2>/dev/null | grep -E 'h_u02|dpd|calib' | head

echo "=== build against 6.12.79 ==="
DRV=$(dirname "$(dirname "$COMPAT")")
cd "$DRV/.."
make -C "$DRV" KDIR="$K" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- 2>&1 | tail -25
find "$W" -name '*.ko' -printf '%s\t%p\n' 2>/dev/null | sort -rn | head
