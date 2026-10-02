#!/usr/bin/env python3
"""k72-aic-proto2.py - print the FULL (untruncated) 7.2.8 prototypes and the
driver's full definitions for exactly the callbacks that need compat wrappers."""
import re

K = "/root/r36/linux-7.2.8/include/net/cfg80211.h"
M = "/root/r36/k72aic/drivers/aic8800/aic8800_fdrv/rwnx_main.c"

hdr = open(K, encoding="utf-8", errors="replace").read()
body = re.search(r"struct cfg80211_ops \{(.*?)\n\};", hdr, re.S).group(1)
body = re.sub(r"/\*.*?\*/", " ", body, flags=re.S)
flat = re.sub(r"\s+", " ", body)

OPS = ["scan", "add_key", "get_key", "del_key", "set_default_key",
       "set_default_mgmt_key", "add_station", "del_station", "change_station",
       "get_station", "dump_station", "get_tx_power", "remain_on_channel",
       "cancel_remain_on_channel"]
print("=== kernel 7.2.8 prototypes, full ===")
for op in OPS:
    m = re.search(r"(\w[\w \t\*&]*?)\(\s*\*" + op + r"\s*\)\s*\(([^;]*)\)\s*;", flat)
    if m:
        args = re.sub(r"\s+", " ", m.group(2))
        print(f"  {op}({args});")
    else:
        print(f"  {op}: ???")

drv = open(M, encoding="utf-8", errors="replace").read()
print("\n=== driver definitions (verbatim, first 22 lines each) ===")
for fn in ["rwnx_cfg80211_scan", "rwnx_cfg80211_add_key", "rwnx_cfg80211_get_key",
           "rwnx_cfg80211_del_key", "rwnx_cfg80211_set_default_key",
           "rwnx_cfg80211_set_default_mgmt_key", "rwnx_cfg80211_add_station",
           "rwnx_cfg80211_del_station_compat", "rwnx_cfg80211_change_station",
           "rwnx_cfg80211_get_station", "rwnx_cfg80211_dump_station",
           "rwnx_cfg80211_get_tx_power", "rwnx_cfg80211_remain_on_channel",
           "rwnx_cfg80211_cancel_remain_on_channel"]:
    lines = drv.splitlines()
    start = None
    for i, ln in enumerate(lines):
        if re.match(r"^(static )?(int|void) " + re.escape(fn) + r"\(", ln):
            start = i
            break
    print(f"\n--- {fn} (line {start + 1 if start is not None else '?'})")
    if start is None:
        continue
    for ln in lines[start:start + 20]:
        if ln.strip() == "{":
            print("     {")
            break
        print("    " + ln)
