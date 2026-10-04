#!/bin/bash
# k72-which-driver.sh - the 6.12 boot logs are full of AICWFDBG(LOGINFO) lines
# (chip_id, ### Upload ...h_u02.bin) while the 7.2.8 boot shows only LOGERROR.
# Suspicion: the two .ko were built from DIFFERENT sources - the working image
# uses the radxa-pkg bundle, and I compiled the 7.2.8 modules from the older
# aic8800dc-linux-patched-main tree.  Prove it before debugging anything else.
set -uo pipefail

A=/root/r36/rootfs/lib/modules/6.12.79/extra      # what the working card runs
B=/root/r36/k72test/wifi/drivers/aic8800          # what I built for 7.2.8
R=/root/r36/aic8800-radxa                          # the radxa bundle, if present

echo "=== the module the working 6.12 image ships ==="
for f in "$A"/*.ko; do
  [ -e "$f" ] || continue
  echo "  $(basename "$f")"
  modinfo -F version -F description -F srcversion "$f" 2>/dev/null | sed 's/^/      /'
done
echo "  vermagic: $(modinfo -F vermagic "$A/aic8800_fdrv.ko" 2>/dev/null)"

echo "=== the module I built for 7.2.8 ==="
for f in "$B"/aic8800_fdrv/aic8800_fdrv.ko "$B"/aic_load_fw/aic_load_fw.ko; do
  [ -e "$f" ] || continue
  echo "  $(basename "$f")"
  modinfo -F version -F description -F srcversion "$f" 2>/dev/null | sed 's/^/      /'
done

echo "=== do the two sources differ? ==="
S1=/root/r36/wifi/aic8800dc-linux-patched-main
for d in "$S1" "$R"; do
  [ -d "$d" ] || { echo "  $d : absent"; continue; }
  echo "  --- $d"
  grep -rhoE "chip_sub_id == [0-9]|unsupported id|fmacfw_patch_8800dc_h_u02|RELEASE_DATE[ =]+[0-9_]+" "$d" 2>/dev/null | sort | uniq -c | sort -rn | head -6 | sed 's/^/      /'
  find "$d" -name "*.c" | wc -l | sed 's/^/      .c files: /'
  find "$d" -name "aicwf_usb.c" -printf "      %p\n" | head -2
done

echo "=== dbg level default in each tree (explains the missing LOGINFO) ==="
for d in "$S1" "$R"; do
  [ -d "$d" ] || continue
  echo "  --- $d"
  grep -rn "dbg_level *=" "$d" 2>/dev/null | grep -vE "==|!=" | head -4 | sed 's/^/      /'
done

echo "=== sizes / build ids ==="
for f in "$A/aic8800_fdrv.ko" "$B/aic8800_fdrv/aic8800_fdrv.ko"; do
  [ -e "$f" ] && echo "  $(stat -c '%s B' "$f")  $(basename "$(dirname "$(dirname "$f")")")/$(basename "$f")"
done
echo "=== which-driver check done ==="
