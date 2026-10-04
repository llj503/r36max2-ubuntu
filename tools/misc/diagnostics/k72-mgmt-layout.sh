#!/bin/bash
# k72-mgmt-layout.sh - print the exact nesting of ieee80211_mgmt's action member
# in 7.2.8 so the tdls access path is written from fact, not guesswork.
set -uo pipefail
H=/root/r36/linux-7.2.8/include/linux/ieee80211.h

L=$(grep -n "u8 category;" "$H" | head -1 | cut -d: -f1)
echo "=== 'u8 category;' is at line $L ==="
awk -v s="$L" 'NR>=s-8 && NR<=s+6 {printf "%5d: %s\n", NR, $0}' "$H"

echo "=== structural lines from there to the end of the action member ==="
awk -v s="$L" 'NR>=s && NR<=s+240 {
    if ($0 ~ /union \{/ || $0 ~ /struct *\{/ || $0 ~ /\} __packed/ || $0 ~ /\} u;/ || $0 ~ /\} action;/ || $0 ~ /^\};/)
        printf "%5d: %s\n", NR, $0
}' "$H" | head -20

echo "=== how an in-tree driver reaches tdls_discover_resp in 7.2 ==="
grep -rn "tdls_discover_resp" /root/r36/linux-7.2.8/drivers/net/wireless/ 2>/dev/null | head -5 | sed 's/^/  /'
grep -rn "action\.u\.tdls\|action\.tdls" /root/r36/linux-7.2.8/net/mac80211/*.c 2>/dev/null | head -5 | sed 's/^/  /'

echo "=== the driver's current (post-edit) tdls lines ==="
sed -n '112,126p' /root/r36/k72aic/drivers/aic8800/aic8800_fdrv/rwnx_tdls.c | cat -n | sed 's/^/  /'
