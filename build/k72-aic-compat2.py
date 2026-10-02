#!/usr/bin/env python3
"""k72-aic-compat2.py - round 2 of the AIC 7.2.8 port:
 * the driver's key/station callbacks DO take link_id (compiler: "expected 7,
   have 6"), so the wrappers must pass it through
 * repair the stray backslash my previous regex wrote into the new_sta call
 * sites
 * put <linux/string.h> where rwnx_msg_tx.c will actually see it
 * show the rwnx_tdls 'no member u' code so it can be fixed knowingly
"""
import re

T = "/root/r36/k72aic/drivers/aic8800/aic8800_fdrv"
M = f"{T}/rwnx_main.c"
src = open(M, encoding="utf-8", errors="replace").read()

# --- 1. repair the backslash damage --------------------------------------
bad = src.count("cfg80211_new_sta(\\&") + src.count("cfg80211_del_sta(\\&")
src = src.replace("cfg80211_new_sta(\\&", "cfg80211_new_sta(&")
src = src.replace("cfg80211_del_sta(\\&", "cfg80211_del_sta(&")
print(f"[1] repaired {bad} stray-backslash call sites")

# --- 2. find where HIGH_KERNEL_VERSION2 really is defined ----------------
import subprocess
out = subprocess.run("grep -rn 'define HIGH_KERNEL_VERSION' /root/r36/k72aic/drivers/aic8800/ | head",
                     shell=True, capture_output=True, text=True).stdout.strip()
print("[2] version gates found:\n" + "".join("      " + l + "\n" for l in out.splitlines()))

# --- 3. regenerate the wrappers WITH link_id -----------------------------
start = src.find("/* ---------------------------------------------------------------------")
end = src.find("static struct cfg80211_ops rwnx_cfg80211_ops = {")
if start != -1 and end != -1:
    W = """/* 6.19+/7.x compat: cfg80211_ops callbacks take a wireless_dev now. */
static int rwnx_w_add_key(struct wiphy *wiphy, struct wireless_dev *wdev,
                          int link_id, u8 key_index, bool pairwise,
                          const u8 *mac_addr, struct key_params *params)
{
    return rwnx_cfg80211_add_key(wiphy, wdev->netdev, link_id, key_index,
                                 pairwise, mac_addr, params);
}

static int rwnx_w_get_key(struct wiphy *wiphy, struct wireless_dev *wdev,
                          int link_id, u8 key_index, bool pairwise,
                          const u8 *mac_addr, void *cookie,
                          void (*callback)(void *cookie, struct key_params *))
{
    return rwnx_cfg80211_get_key(wiphy, wdev->netdev, link_id, key_index,
                                 pairwise, mac_addr, cookie, callback);
}

static int rwnx_w_del_key(struct wiphy *wiphy, struct wireless_dev *wdev,
                          int link_id, u8 key_index, bool pairwise,
                          const u8 *mac_addr)
{
    return rwnx_cfg80211_del_key(wiphy, wdev->netdev, link_id, key_index,
                                 pairwise, mac_addr);
}

static int rwnx_w_set_default_mgmt_key(struct wiphy *wiphy, struct wireless_dev *wdev,
                                       int link_id, u8 key_index)
{
    return rwnx_cfg80211_set_default_mgmt_key(wiphy, wdev->netdev, link_id, key_index);
}

static int rwnx_w_add_station(struct wiphy *wiphy, struct wireless_dev *wdev,
                              const u8 *mac, struct station_parameters *params)
{
    return rwnx_cfg80211_add_station(wiphy, wdev->netdev, mac, params);
}

static int rwnx_w_del_station(struct wiphy *wiphy, struct wireless_dev *wdev,
                              struct station_del_parameters *params)
{
    return rwnx_cfg80211_del_station_compat(wiphy, wdev->netdev, params);
}

static int rwnx_w_change_station(struct wiphy *wiphy, struct wireless_dev *wdev,
                                 const u8 *mac, struct station_parameters *params)
{
    return rwnx_cfg80211_change_station(wiphy, wdev->netdev, mac, params);
}

static int rwnx_w_get_station(struct wiphy *wiphy, struct wireless_dev *wdev,
                              const u8 *mac, struct station_info *sinfo)
{
    return rwnx_cfg80211_get_station(wiphy, wdev->netdev, mac, sinfo);
}

static int rwnx_w_dump_station(struct wiphy *wiphy, struct wireless_dev *wdev,
                               int idx, u8 *mac, struct station_info *sinfo)
{
    return rwnx_cfg80211_dump_station(wiphy, wdev->netdev, idx, mac, sinfo);
}

static int rwnx_w_get_tx_power(struct wiphy *wiphy, struct wireless_dev *wdev,
                               int radio_idx, unsigned int link_id, int *mbm)
{
    return rwnx_cfg80211_get_tx_power(wiphy, wdev, mbm);
}

static int rwnx_w_cancel_remain_on_channel(struct wiphy *wiphy,
                                           struct wireless_dev *wdev, u64 cookie)
{
    return rwnx_cfg80211_cancel_remain_on_channel(wiphy, wdev, cookie);
}

"""
    src = src[:start] + W + src[end:]
    print("[3] wrappers regenerated with link_id threaded through")
else:
    print("[3] wrapper block not located")

# cancel_remain_on_channel may already match; drop a wrapper the table does not use
src = src.replace(".cancel_remain_on_channel = rwnx_cfg80211_cancel_remain_on_channel",
                  ".cancel_remain_on_channel = rwnx_w_cancel_remain_on_channel")
open(M, "w").write(src)

# --- 4. rwnx_msg_tx.c: show the include block and fix it ----------------
tx_path = f"{T}/rwnx_msg_tx.c"
tx = open(tx_path).read()
print("[4] rwnx_msg_tx.c includes:")
for i, ln in enumerate(tx.splitlines()[:24], 1):
    if ln.startswith("#include") or "string.h" in ln:
        print(f"      {i}: {ln}")
if "#include <linux/string.h>" not in tx:
    m = re.search(r"#include\s+<linux/module\.h>", tx)
    if m:
        tx = tx[:m.end()] + "\n#include <linux/string.h>" + tx[m.end():]
    else:
        m = re.search(r"#include\s*[<\"][^>\"]+[>\"]", tx)
        tx = tx[:m.end()] + "\n#include <linux/string.h>" + tx[m.end():]
    open(tx_path, "w").write(tx)
    print("      added <linux/string.h> at the top")

# --- 5. show the tdls problem ------------------------------------------
td = open(f"{T}/rwnx_tdls.c").read().splitlines()
print("[5] rwnx_tdls.c 100-130:")
for i in range(99, min(131, len(td))):
    print(f"      {i+1}: {td[i]}")
