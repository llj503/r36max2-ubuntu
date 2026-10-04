#!/usr/bin/env python3
"""k72-aic-compat3.py - round 3:
 * 7.2 made the union inside ieee80211_mgmt's `action` anonymous, so
   mgmt->u.action.u.X  ->  mgmt->u.action.X
 * strncpy() was removed from the kernel; the one call site becomes strscpy().
Then rebuild and report what is left.
"""
import re
import subprocess

T = "/root/r36/k72aic/drivers/aic8800/aic8800_fdrv"

# --- tdls union ---------------------------------------------------------
p = f"{T}/rwnx_tdls.c"
s = open(p).read()
n = s.count(".action.u.")
s = s.replace(".action.u.", ".action.")
open(p, "w").write(s)
print(f"[1] rwnx_tdls.c: dropped {n} anonymous-union hops (.action.u. -> .action.)")

# --- strncpy ------------------------------------------------------------
p = f"{T}/rwnx_msg_tx.c"
s = open(p).read()
hits = re.findall(r"strncpy\([^;]*\);", s)
print(f"[2] rwnx_msg_tx.c strncpy sites: {len(hits)}")
for h in hits:
    print("      " + h.strip()[:150])
s2 = re.sub(r"\bstrncpy\(", "strscpy(", s)
if s2 != s:
    open(p, "w").write(s2)
    print("    -> replaced with strscpy (same 3-argument shape)")

# --- rebuild ------------------------------------------------------------
print("[3] rebuilding ...")
r = subprocess.run("cd /root/r36/k72aic/drivers/aic8800 && make -C . "
                   "KDIR=/root/r36/linux-7.2.8 ARCH=arm64 "
                   "CROSS_COMPILE=aarch64-linux-gnu- 2>&1 | tail -60",
                   shell=True, capture_output=True, text=True)
out = r.stdout + r.stderr
open("/mnt/e/ubuntu/logs/aic72-errors3.log", "w").write(out)
errs = re.findall(r"^.*?error:.*$", out, re.M)
print(f"    errors now: {len(errs)}")
for e in sorted(set(errs))[:20]:
    print("      " + e[:170])
kos = subprocess.run("find /root/r36/k72aic -name '*.ko' -printf '  %p  %s bytes\\n'",
                     shell=True, capture_output=True, text=True).stdout
print("=== produced ===" )
print(kos or "  (none)")
