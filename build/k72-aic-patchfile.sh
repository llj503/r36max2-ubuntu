#!/bin/bash
# k72-aic-patchfile.sh - regenerate the compat patch from SOURCE FILES ONLY
# (the first attempt dragged in .o/.cmd build artifacts and came out 6.5 MB).
set -uo pipefail
SRC=/root/r36/aic8800-radxa/src/USB/driver_fw/drivers/aic8800
NEW=/root/r36/k72aic/drivers/aic8800
OUT=/mnt/e/ubuntu/build/aic8800-7.2.8-compat.patch

cd / && diff -ruN \
    --exclude='*.o' --exclude='*.o.d' --exclude='.*.cmd' --exclude='*.ko' \
    --exclude='*.mod' --exclude='*.mod.c' --exclude='Module.symvers' \
    --exclude='modules.order' --exclude='.tmp_*' --exclude='*.symvers' \
    "$SRC" "$NEW" > /tmp/aicc.patch 2>/dev/null
grep -vE "^Only in " /tmp/aicc.patch > "$OUT"
echo "wrote $OUT: $(wc -l < "$OUT") lines, $(du -h "$OUT" | cut -f1)"
echo "=== files touched ==="
grep -E "^\+\+\+ " "$OUT" | sed 's|.*/aic8800/||;s|\t.*||' | sed 's/^/  /'
echo "=== summary of the changes ==="
grep -cE "^\+" "$OUT" | sed 's/^/  added lines:   /'
grep -cE "^-" "$OUT" | sed 's/^/  removed lines: /'
grep -nE "^[+-].*(strscpy|in_hardirq|wireless_dev \*wdev|rwnx_w_|action_code|linux/string.h|linux/hex.h)" "$OUT" | head -20 | sed 's/^/  /'
