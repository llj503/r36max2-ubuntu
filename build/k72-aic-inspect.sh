#!/bin/bash
# k72-aic-inspect.sh - dump exactly what the port needs: the ops table, the
# current callback signatures that mismatch, the two cfg80211_new_sta/del_sta
# call sites, and the rwnx_tdls 'no member u' code.
set -uo pipefail
T=/root/r36/k72aic/drivers/aic8800
M=$T/aic8800_fdrv/rwnx_main.c
D=$T/aic8800_fdrv/rwnx_tdls.c

echo "=== ops table (6400-6440) ==="
sed -n '6400,6440p' "$M" | cat -n | sed 's/^/  /'
echo "=== the two dynamic assignments (6545-6555) ==="
sed -n '6545,6556p' "$M" | sed 's/^/  /'
echo "=== new_sta / del_sta call sites ==="
sed -n '3545,3555p' "$M" | sed 's/^/  /'
sed -n '3662,3670p' "$M" | sed 's/^/  /'
echo "=== signatures that must be wrapped ==="
for fn in rwnx_cfg80211_add_key rwnx_cfg80211_get_key rwnx_cfg80211_del_key rwnx_cfg80211_set_default_key rwnx_cfg80211_add_station rwnx_cfg80211_del_station_compat rwnx_cfg80211_change_station rwnx_cfg80211_get_station rwnx_cfg80211_dump_station rwnx_cfg80211_dump_survey rwnx_cfg80211_remain_on_channel rwnx_cfg80211_cancel_remain_on_channel rwnx_cfg80211_get_mpath; do
  grep -n -A3 "^static int $fn(" "$M" | head -5 | sed 's/^/  /'
  echo "  ---"
done
echo "=== rwnx_tdls.c 105-130 ==="
sed -n '105,130p' "$D" | sed 's/^/  /'
echo "=== what 7.2 station_parameters/ie looks like there ==="
grep -n "struct element" /root/r36/linux-7.2.8/include/linux/ieee80211.h | head -5 | sed 's/^/  /'
echo "=== inspect done ==="
