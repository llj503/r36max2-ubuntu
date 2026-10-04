#!/bin/bash
# Copy the driver source to E: so I can read/edit it with proper tooling.
set -e
REPO=${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
SRC=/root/r36/wifi/aic8800dc-linux-patched-main/drivers/aic8800
DST=$REPO/build/aic-src
rm -rf "$DST"; mkdir -p "$DST"
cp -a "$SRC"/. "$DST"/
find "$DST" -name '*.o' -delete; find "$DST" -name '*.ko' -delete; find "$DST" -name '*.mod*' -delete
du -sh "$DST"
echo "=== every chip_sub_id decision point in the fdrv ==="
grep -rn 'chip_sub_id' "$DST/aic8800_fdrv/"*.c "$DST/aic8800_fdrv/"*.h
echo "=== every firmware name macro / request_firmware user in the fdrv ==="
grep -rnE '_u02|u02h|calib|patch_tbl|RWNX_MAC_(FW|PATCH|RF)[A-Z_0-9]*' "$DST/aic8800_fdrv/"*.c "$DST/aic8800_fdrv/"*.h | grep -vE '^\S+:[0-9]+:\s*//' | head -40
