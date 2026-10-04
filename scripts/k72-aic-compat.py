#!/usr/bin/env python3
"""k72-aic-compat.py - port the radxa AIC8800 driver to 7.2.8's cfg80211 API.

The kernel moved most cfg80211_ops callbacks from (wiphy, net_device *) to
(wiphy, wireless_dev *) and tweaked a few argument lists.  Rather than rewrite
the driver bodies (they use netdev everywhere), add thin wrappers with the new
prototype that forward to the existing functions, and point the ops table at
them.  Also: in_irq() -> in_hardirq(), explicit <linux/string.h>, and the two
cfg80211_new_sta/del_sta call sites.
"""
import re
import subprocess

T = "/root/r36/k72aic/drivers/aic8800/aic8800_fdrv"
M = f"{T}/rwnx_main.c"

src = open(M, encoding="utf-8", errors="replace").read()
orig = src

# --- how does the driver gate the link_id arguments? ----------------------
hv = {}
for name in ("HIGH_KERNEL_VERSION", "HIGH_KERNEL_VERSION2", "HIGH_KERNEL_VERSION3"):
    m = re.search(r"#define\s+" + name + r"\s+KERNEL_VERSION\((\d+),\s*(\d+),\s*(\d+)\)", src)
    if m:
        hv[name] = tuple(int(x) for x in m.groups())
print("version gates in the driver:", hv or "none found")
kver = (7, 2, 8)
def at_least(name, default=(99, 0, 0)):
    v = hv.get(name, default)
    return v <= kver
LINK = at_least("HIGH_KERNEL_VERSION2")
print(f"  building for {kver}: link_id args present in the driver? {LINK}")

lk = ", int link_id" if LINK else ""
lk_pass = ", link_id" if LINK else ""

WRAPPERS = f"""
/* ---------------------------------------------------------------------
 * 6.19+/7.x compat: cfg80211_ops callbacks now receive a wireless_dev
 * instead of a net_device.  Keep the driver's implementations untouched
 * and forward through these wrappers.  Generated while porting to 7.2.8.
 * ------------------------------------------------------------------ */
static int rwnx_w_add_key(struct wiphy *wiphy, struct wireless_dev *wdev{lk},
                          u8 key_index, bool pairwise, const u8 *mac_addr,
                          struct key_params *params)
{{
    return rwnx_cfg80211_add_key(wiphy, wdev->netdev{lk_pass}, key_index,
                                 pairwise, mac_addr, params);
}}

static int rwnx_w_get_key(struct wiphy *wiphy, struct wireless_dev *wdev{lk},
                          u8 key_index, bool pairwise, const u8 *mac_addr,
                          void *cookie,
                          void (*callback)(void *cookie, struct key_params *))
{{
    return rwnx_cfg80211_get_key(wiphy, wdev->netdev{lk_pass}, key_index,
                                 pairwise, mac_addr, cookie, callback);
}}

static int rwnx_w_del_key(struct wiphy *wiphy, struct wireless_dev *wdev{lk},
                          u8 key_index, bool pairwise, const u8 *mac_addr)
{{
    return rwnx_cfg80211_del_key(wiphy, wdev->netdev{lk_pass}, key_index,
                                 pairwise, mac_addr);
}}

static int rwnx_w_set_default_mgmt_key(struct wiphy *wiphy, struct wireless_dev *wdev{lk},
                                       u8 key_index)
{{
    return rwnx_cfg80211_set_default_mgmt_key(wiphy, wdev->netdev{lk_pass}, key_index);
}}

static int rwnx_w_add_station(struct wiphy *wiphy, struct wireless_dev *wdev,
                              const u8 *mac, struct station_parameters *params)
{{
    return rwnx_cfg80211_add_station(wiphy, wdev->netdev, mac, params);
}}

static int rwnx_w_del_station(struct wiphy *wiphy, struct wireless_dev *wdev,
                              struct station_del_parameters *params)
{{
    return rwnx_cfg80211_del_station_compat(wiphy, wdev->netdev, params);
}}

static int rwnx_w_change_station(struct wiphy *wiphy, struct wireless_dev *wdev,
                                 const u8 *mac, struct station_parameters *params)
{{
    return rwnx_cfg80211_change_station(wiphy, wdev->netdev, mac, params);
}}

static int rwnx_w_get_station(struct wiphy *wiphy, struct wireless_dev *wdev,
                              const u8 *mac, struct station_info *sinfo)
{{
    return rwnx_cfg80211_get_station(wiphy, wdev->netdev, mac, sinfo);
}}

static int rwnx_w_dump_station(struct wiphy *wiphy, struct wireless_dev *wdev,
                               int idx, u8 *mac, struct station_info *sinfo)
{{
    return rwnx_cfg80211_dump_station(wiphy, wdev->netdev, idx, mac, sinfo);
}}

static int rwnx_w_get_tx_power(struct wiphy *wiphy, struct wireless_dev *wdev,
                               int radio_idx, unsigned int link_id, int *dbm)
{{
    return rwnx_cfg80211_get_tx_power(wiphy, wdev, dbm);
}}

static int rwnx_w_remain_on_channel(struct wiphy *wiphy, struct wireless_dev *wdev,
                                    struct ieee80211_channel *chan,
                                    unsigned int duration, u64 *cookie,
                                    const u8 *rx_addr)
{{
    return rwnx_cfg80211_remain_on_channel(wiphy, wdev, chan, duration, cookie);
}}

static int rwnx_w_cancel_remain_on_channel(struct wiphy *wiphy, struct wireless_dev *wdev,
                                           u64 cookie)
{{
    return rwnx_cfg80211_cancel_remain_on_channel(wiphy, wdev, cookie);
}}
"""

# get_tx_power / remain_on_channel already take a wiphy-only or wdev form in
# this driver; fix their forwarding once we know the real signature.
m = re.search(r"static int rwnx_cfg80211_get_tx_power\((.*?)\)\s*\{", src, re.S)
print("driver get_tx_power params:", re.sub(r"\s+", " ", m.group(1)) if m else "?")
m2 = re.search(r"static int rwnx_cfg80211_remain_on_channel\((.*?)\)\s*\{", src, re.S)
print("driver remain_on_channel params:", re.sub(r"\s+", " ", m2.group(1)) if m2 else "?")

# --- insert the wrappers before the ops table ----------------------------
anchor = "static struct cfg80211_ops rwnx_cfg80211_ops = {"
if "rwnx_w_add_key" not in src and anchor in src:
    src = src.replace(anchor, WRAPPERS + "\n" + anchor, 1)
    print("[4] inserted compat wrappers before the ops table")
else:
    print("[4] wrappers already present or anchor missing")

# --- point the ops table at them -----------------------------------------
SWAP = {
    ".add_key": "rwnx_cfg80211_add_key",
    ".get_key": "rwnx_cfg80211_get_key",
    ".del_key": "rwnx_cfg80211_del_key",
    ".set_default_mgmt_key": "rwnx_cfg80211_set_default_mgmt_key",
    ".add_station": "rwnx_cfg80211_add_station",
    ".del_station": "rwnx_cfg80211_del_station_compat",
    ".change_station": "rwnx_cfg80211_change_station",
    ".get_station": "rwnx_cfg80211_get_station",
    ".get_tx_power": "rwnx_cfg80211_get_tx_power",
    ".remain_on_channel": "rwnx_cfg80211_remain_on_channel",
    ".cancel_remain_on_channel": "rwnx_cfg80211_cancel_remain_on_channel",
}
tbl_start = src.find(anchor)
tbl_end = src.find("\n};", tbl_start)
table = src[tbl_start:tbl_end]
for key, old in SWAP.items():
    new = old.replace("rwnx_cfg80211_", "rwnx_w_")
    if new == "rwnx_w_del_station_compat":
        new = "rwnx_w_del_station"
    table = table.replace(f"{key} = {old}", f"{key} = {new}")
src = src[:tbl_start] + table + src[tbl_end:]
print("[5] ops table entries redirected to the wrappers")

# --- the mesh assignments further down ----------------------------------
src = src.replace("rwnx_cfg80211_ops.get_station = rwnx_cfg80211_get_station;",
                  "rwnx_cfg80211_ops.get_station = rwnx_w_get_station;")
src = src.replace("rwnx_cfg80211_ops.dump_station = rwnx_cfg80211_dump_station;",
                  "rwnx_cfg80211_ops.dump_station = rwnx_w_dump_station;")

# --- cfg80211_new_sta / cfg80211_del_sta now want a wdev ----------------
n1 = len(re.findall(r"cfg80211_new_sta\(", src))
src = re.sub(r"cfg80211_new_sta\((\w+)->ndev,", r"cfg80211_new_sta(\&\1->wdev,", src)
src = re.sub(r"cfg80211_del_sta\((\w+)->ndev,", r"cfg80211_del_sta(\&\1->wdev,", src)
print(f"[3] rewrote cfg80211_new_sta call sites (found {n1})")

if src != orig:
    open(M + ".bak", "w").write(orig)
    open(M, "w").write(src)
    print("wrote", M)

# --- rwnx_rx.c in_irq, rwnx_msg_tx.c string.h ---------------------------
rx = open(f"{T}/rwnx_rx.c").read()
if "in_irq()" in rx:
    rx = rx.replace("in_irq()", "in_hardirq()")
    open(f"{T}/rwnx_rx.c", "w").write(rx)
    print("[1] rwnx_rx.c: in_irq() -> in_hardirq()")
tx = open(f"{T}/rwnx_msg_tx.c").read()
if "#include <linux/string.h>" not in tx:
    tx = tx.replace("#include <rwnx_msg_tx.h>", "#include <linux/string.h>\n#include <rwnx_msg_tx.h>", 1)
    if "#include <linux/string.h>" not in tx:
        tx = re.sub(r"(#include <linux/[a-z_/]+\.h>)", r"\1\n#include <linux/string.h>", tx, count=1)
    open(f"{T}/rwnx_msg_tx.c", "w").write(tx)
    print("[2] rwnx_msg_tx.c: added <linux/string.h>")
else:
    print("[2] rwnx_msg_tx.c already includes string.h")
