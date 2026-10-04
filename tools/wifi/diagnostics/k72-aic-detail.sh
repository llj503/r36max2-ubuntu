#!/bin/bash
# k72-aic-detail.sh - confirm (a) whether the action union is now anonymous and
# (b) whether strncpy still exists in the kernel headers at all.
set -uo pipefail
K=/root/r36/linux-7.2.8
T=/root/r36/k72aic/drivers/aic8800/aic8800_fdrv

echo "=== ieee80211.h around the action union (1060-1120) ==="
sed -n '1060,1075p;1100,1120p' "$K/include/linux/ieee80211.h" | sed 's/^/  /'
echo "=== is there a '} u;' inside struct ieee80211_mgmt? ==="
awk '/^struct ieee80211_mgmt \{/,/^\};/' "$K/include/linux/ieee80211.h" | grep -nE "\} (u|action)\s*;|union \{" | sed 's/^/  /'

echo
echo "=== strncpy / strscpy in 7.2 headers ==="
grep -rn "strncpy" "$K/include/linux/string.h" | head -5 | sed 's/^/  /' || echo "  no strncpy in linux/string.h"
grep -n "define strscpy\|__must_check size_t strscpy\|strscpy(" "$K/include/linux/string.h" | head -6 | sed 's/^/  /'
echo "=== the driver's strncpy call ==="
sed -n '4846,4858p' "$T/rwnx_msg_tx.c" | sed 's/^/  /'
echo "=== the tdls access path in 7.2 terms ==="
grep -n "tdls_discover_resp" "$K/include/linux/ieee80211.h" | sed 's/^/  /'
sed -n '1104,1112p' "$K/include/linux/ieee80211.h" | sed 's/^/  /'
echo "=== detail done ==="
