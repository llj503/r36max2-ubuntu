#!/usr/bin/env python3
"""k72-aic-compat4.py - last error: the ops table points at
rwnx_w_remain_on_channel but round 3 dropped that wrapper.  Print the driver's
real remain_on_channel signature, add the matching wrapper, rebuild."""
import re
import subprocess

T = "/root/r36/k72aic/drivers/aic8800/aic8800_fdrv"
M = f"{T}/rwnx_main.c"
s = open(M).read()

m = re.search(r"static int rwnx_cfg80211_remain_on_channel\(([\s\S]{0,400}?)\)\s*\{", s)
print("driver remain_on_channel signature:")
print(m.group(0)[:400] if m else "  NOT FOUND - searching for any spelling")
if not m:
    for line in s.splitlines():
        if "remain_on_channel" in line:
            print("   |", line[:150])

# kernel 7.2: (wiphy, wdev, chan, duration, u64 *cookie, const u8 *rx_addr)
# build a wrapper that forwards everything the driver accepts and ignores rx_addr
W = """
static int rwnx_w_remain_on_channel(struct wiphy *wiphy, struct wireless_dev *wdev,
                                    struct ieee80211_channel *chan,
                                    unsigned int duration, u64 *cookie,
                                    const u8 *rx_addr)
{
    return rwnx_cfg80211_remain_on_channel(wiphy, wdev, chan, duration, cookie);
}

"""
anchor = "static struct cfg80211_ops rwnx_cfg80211_ops = {"
if "rwnx_w_remain_on_channel(" not in s:
    s = s.replace(anchor, W + anchor, 1)
    open(M, "w").write(s)
    print("[+] added rwnx_w_remain_on_channel wrapper")
else:
    print("[=] wrapper already present")

r = subprocess.run("cd /root/r36/k72aic/drivers/aic8800 && make -C . "
                   "KDIR=/root/r36/linux-7.2.8 ARCH=arm64 "
                   "CROSS_COMPILE=aarch64-linux-gnu- 2>&1 | tail -40",
                   shell=True, capture_output=True, text=True)
out = r.stdout + r.stderr
open("/mnt/e/ubuntu/logs/aic72-errors4.log", "w").write(out)
errs = re.findall(r".*error:.*", out)
warn = re.findall(r"warning:.*", out)
print(f"errors: {len(errs)}   warnings: {len(warn)}")
for e in errs[:15]:
    print("   " + e[:170])
for w in warn[:8]:
    print("   W " + w[:150])
print("=== modules produced ===")
print(subprocess.run("find /root/r36/k72aic -name '*.ko' -printf '  %p  %s bytes\\n'",
                     shell=True, capture_output=True, text=True).stdout or "  (none)")
