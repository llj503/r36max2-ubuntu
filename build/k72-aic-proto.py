#!/usr/bin/env python3
"""k72-aic-proto.py - extract the 7.2.8 cfg80211_ops prototypes and the AIC
driver's current callbacks so the compat wrappers can be written from text."""
import re

K = "/root/r36/linux-7.2.8/include/net/cfg80211.h"
M = "/root/r36/k72aic/drivers/aic8800/aic8800_fdrv/rwnx_main.c"

hdr = open(K, encoding="utf-8", errors="replace").read()
body = re.search(r"struct cfg80211_ops \{(.*?)\n\};", hdr, re.S).group(1)
body = re.sub(r"/\*.*?\*/", " ", body, flags=re.S)          # drop kerneldoc
body = re.sub(r"^\s*#.*$", "", body, flags=re.M)            # drop preprocessor
ops = {}
for m in re.finditer(r"[A-Za-z_][\w \t\*&\(\),\[\]:]*?\(\s*\*(\w+)\s*\)\s*\(([^;]*)\)\s*;",
                     re.sub(r"\s+", " ", body)):
    name, args = m.group(1), re.sub(r"\s+", " ", m.group(2)).strip()
    ops[name] = args

drv = open(M, encoding="utf-8", errors="replace").read()
drv_nocomment = re.sub(r"/\*.*?\*/", " ", drv, flags=re.S)
table = re.search(r"struct cfg80211_ops rwnx_cfg80211_ops = \{(.*?)\n\};", drv_nocomment, re.S)
entries = {}
for m in re.finditer(r"\.(\w+)\s*=\s*(\w+)", table.group(1) if table else ""):
    entries[m.group(1)] = m.group(2)

WANT = ["add_key", "get_key", "del_key", "set_default_key", "set_default_mgmt_key",
        "add_station", "del_station", "change_station", "get_station", "dump_station",
        "get_tx_power", "remain_on_channel", "cancel_remain_on_channel", "dump_survey",
        "change_beacon", "add_mpath", "del_mpath", "change_mpath", "get_mpath",
        "probe_client", "start_ap", "stop_ap", "scan", "connect", "disconnect",
        "set_power_mgmt", "get_channel", "set_monitor_channel", "update_ft_ies",
        "set_wiphy_params", "set_txq_params", "set_tx_power", "start_radar_detection",
        "mgmt_tx", "add_virtual_intf", "del_virtual_intf", "change_virtual_intf",
        "start_p2p_device", "stop_p2p_device", "set_cqm_rssi_config"]

def driver_sig(fn):
    m = re.search(r"^(?:static )?int " + re.escape(fn) + r"\((.*?)\)\s*\{",
                  drv_nocomment, re.S | re.M)
    if not m:
        return None
    return re.sub(r"\s+", " ", m.group(1)).strip()

print("op                          kernel 7.2.8 prototype                          | driver callback -> its signature")
print("-" * 150)
for op in WANT:
    if op not in entries:
        continue
    kproto = ops.get(op, "MEMBER GONE")
    cb = entries[op]
    dsig = driver_sig(cb) or "?"
    flag = ""
    knetdev = "struct net_device *dev" in kproto or "struct net_device *netdev" in kproto
    dnetdev = "struct net_device *" in dsig
    if knetdev != dnetdev:
        flag = "  <== NETDEV/WDEV MISMATCH"
    elif kproto.count(",") != dsig.count(","):
        flag = "  <== ARGC DIFFERS"
    print(f"{op:<27} {kproto[:52]:<52} | {cb}({dsig[:60]}){flag}")
print()
print("=== ops members the kernel no longer has (driver assigns them anyway) ===")
for op, cb in entries.items():
    if op not in ops:
        print(f"  .{op} = {cb}   <- not in 7.2.8 cfg80211_ops")
print()
print("=== cfg80211_new_sta / del_sta prototypes ===")
for fn in ("cfg80211_new_sta", "cfg80211_del_sta"):
    m = re.search(r"(?:void|int) " + fn + r"\(([^;]*?)\);", hdr, re.S)
    print(f"  {fn}({re.sub(chr(10)+'|'+chr(9), ' ', m.group(1)) if m else '?'})")
