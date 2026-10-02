#!/bin/bash
# k72-aic-tdls.sh - what did 7.2 rename the ieee80211_mgmt action union members
# to, and where did my earlier string.h insertion actually land?
set -uo pipefail
K=/root/r36/linux-7.2.8
T=/root/r36/k72aic/drivers/aic8800/aic8800_fdrv

echo "=== ieee80211_mgmt action union in 7.2 ==="
awk '/^struct ieee80211_mgmt \{/,/^\};/' "$K/include/linux/ieee80211.h" | grep -nE "struct \{|tdls|\} u;|category|action" | head -40 | sed 's/^/  /'

echo "=== tdls structs available ==="
grep -n "struct ieee80211_mgmt" -A200 "$K/include/linux/ieee80211.h" | grep -E "_tdls|tdls_" | head -20 | sed 's/^/  /'

echo "=== where did string.h land in rwnx_msg_tx.c? ==="
grep -n "string.h" "$T/rwnx_msg_tx.c" | sed 's/^/  /'
echo "  first 6 include lines:"
grep -n "^#include" "$T/rwnx_msg_tx.c" | head -6 | sed 's/^/    /'
echo "=== the strncpy site ==="
sed -n '4845,4860p' "$T/rwnx_msg_tx.c" | sed 's/^/  /'
echo "=== tdls query done ==="
