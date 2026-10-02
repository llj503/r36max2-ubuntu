#!/bin/bash
# k72-aic-errors.sh - collect the COMPLETE list of 7.2.8 API errors in the radxa
# AIC driver, grouped, so the cfg80211 netdev->wdev port can be done in one
# pass instead of one build per fix.
set -uo pipefail
K=/root/r36/linux-7.2.8
T=/root/r36/k72aic/drivers/aic8800
X=ARCH=arm64
CROSS=CROSS_COMPILE=aarch64-linux-gnu-
cd "$T" || exit 1

make -C "$T" KDIR="$K" $X $CROSS > /tmp/aic72.log 2>&1
echo "=== error count: $(grep -c 'error:' /tmp/aic72.log) ==="
echo "=== by file ==="
grep -oE "[a-z_0-9]+\.[c]:[0-9]+" /tmp/aic72.log | cut -d: -f1 | sort | uniq -c | sort -rn | sed 's/^/  /'
echo "=== by kind ==="
grep -oE "error: [a-z' ]+" /tmp/aic72.log | sort | uniq -c | sort -rn | head -10 | sed 's/^/  /'
echo "=== the cfg80211_ops table as the driver writes it ==="
sed -n '/static const struct cfg80211_ops cfg80211_ops/,/};/p' aic8800_fdrv/rwnx_main.c | head -45 | sed 's/^/  /'
echo "=== what 7.2.8 expects for the ops we tripped over ==="
for fn in add_key get_key del_key set_default_key change_station del_station get_station dump_station remain_on_channel cancel_remain_on_channel testmode_cmd start_ap stop_ap; do
  grep -A3 "\*@$fn\b" "$K/include/net/cfg80211.h" 2>/dev/null | grep -oE "@$fn[^*]*" | head -1 | sed 's/^/  /'
done
echo "=== which driver callbacks already take wdev vs netdev ==="
grep -nE "^static int rwnx_(cfg80211_)?(add|get|del|set_default|change|dump|remain|cancel)" aic8800_fdrv/rwnx_main.c | head -20 | sed 's/^/  /'
echo "=== in_irq / strncpy sites ==="
grep -rn "in_irq()" aic8800_fdrv/*.c aic_load_fw/*.c 2>/dev/null | sed 's/^/  /'
grep -c "strncpy" aic8800_fdrv/rwnx_msg_tx.c | sed 's/^/  strncpy in rwnx_msg_tx.c: /'
echo "=== errors saved at \/tmp\/aic72.log (copy to Windows) ==="
cp /tmp/aic72.log /mnt/e/ubuntu/logs/aic72-errors.log && echo "  -> E:\ubuntu\logs\aic72-errors.log"
