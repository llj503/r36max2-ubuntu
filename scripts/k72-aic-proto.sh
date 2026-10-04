#!/bin/bash
# k72-aic-proto.sh - print the EXACT 7.2.8 prototypes for every cfg80211_ops
# member the AIC driver assigns, plus the driver's own current signature, so the
# compat wrappers can be written from text rather than from the compiler's
# truncated messages.
set -uo pipefail
K=/root/r36/linux-7.2.8
H=$K/include/net/cfg80211.h
M=/root/r36/k72aic/drivers/aic8800/aic8800_fdrv/rwnx_main.c

ops=$(awk '/^struct cfg80211_ops \{/,/^\};/' "$H" | grep -oE "^\t[a-z_0-9]+\(" | tr -d '\t(' | sort -u)
echo "=== kernel 7.2.8 prototypes (the ones AIC assigns) ==="
for op in add_key get_key del_key set_default_key set_default_mgmt_key add_station del_station change_station get_station dump_station get_tx_power remain_on_channel cancel_remain_on_channel dump_survey change_beacon add_mpath del_mpath change_mpath get_mpath probe_client start_ap stop_ap; do
  # declaration inside struct cfg80211_ops: may span lines until ';'
  line=$(awk -v fn=".$op" 'BEGIN{p=0} $0 ~ "^\t[a-z_0-9 \\*]+\(\s*\*?"fn if(p==0){p=1} p{printf "%s ", $0} p&&/;/{print ""; exit}' "$H")
  printf '  %-26s %s\n' "$op" "${line:-NOT IN cfg80211_ops}"
done

echo
echo "=== driver's current signature for the same names ==="
for fn in rwnx_cfg80211_add_key rwnx_cfg80211_get_key rwnx_cfg80211_del_key rwnx_cfg80211_set_default_key rwnx_cfg80211_set_default_mgmt_key rwnx_cfg80211_add_station rwnx_cfg80211_del_station_compat rwnx_cfg80211_change_station rwnx_cfg80211_get_station rwnx_cfg80211_dump_station rwnx_cfg80211_get_tx_power rwnx_cfg80211_remain_on_channel rwnx_cfg80211_cancel_remain_on_channel rwnx_cfg80211_dump_survey rwnx_cfg80211_change_beacon rwnx_cfg80211_add_mpath rwnx_cfg80211_del_mpath rwnx_cfg80211_get_mpath rwnx_cfg80211_change_mpath; do
  sig=$(awk -v fn="$fn(" 'index($0, fn)==1{f=1} f{printf "%s ", $0} f&&/\)\n?$|\);?$|^\{$/{exit}' "$M" | cut -c1-190)
  printf '  %-40s %s\n' "$fn" "${sig:-not found}"
done

echo
echo "=== HIGH_KERNEL_VERSION* macros the driver already uses ==="
grep -rn "define HIGH_KERNEL_VERSION" /root/r36/k72aic/drivers/aic8800/ | sed 's/^/  /'
echo "=== proto dump done ==="
