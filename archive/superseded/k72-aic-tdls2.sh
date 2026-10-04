#!/bin/bash
# k72-aic-tdls2.sh - 7.2 hoisted `action_code` out of the per-action structs into
# ieee80211_mgmt.action itself (mac80211 does mgmt->u.action.action_code now),
# so tdls_discover_resp no longer has that member.  Fix the path and rebuild.
set -uo pipefail
T=/root/r36/k72aic/drivers/aic8800/aic8800_fdrv
F=$T/rwnx_tdls.c

echo "=== before ==="
grep -n "action_code" "$F" | head -8 | sed 's/^/  /'
sed -i 's/->u\.action\.tdls_discover_resp\.action_code/->u.action.action_code/g' "$F"
sed -i 's/->u\.action\.u\.tdls_discover_resp\.action_code/->u.action.action_code/g' "$F"
echo "=== after ==="
grep -n "action_code" "$F" | head -8 | sed 's/^/  /'

echo "=== rebuild ==="
make -C /root/r36/k72aic/drivers/aic8800 KDIR=/root/r36/linux-7.2.8 \
     ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- modules 2>&1 | \
  grep -E "error:|\.ko|LD \[M\]|MODPOST" | tail -12
echo "=== produced ==="
find /root/r36/k72aic -name "*.ko" -printf "  %p  %s bytes\n"
