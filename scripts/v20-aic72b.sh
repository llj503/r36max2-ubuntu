#!/bin/bash
# v20-aic72b.sh - the previous attempt staged the WRONG modules (the tree holds
# 6.12-built .ko, vermagic proves it, and a build against 7.2.8 without our
# compat patch fails with exactly the errors the patch fixes).  Do it properly:
# clean source copy -> patch with the right -p/-d (the patch paths are relative
# to drivers/) -> build against 7.2.8 -> stage -> prove identity with the bytes
# the running card is using for WiFi.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
K7=/root/r36/linux-7.2.8
AIC=/root/r36/aic8800-radxa/src/USB/driver_fw
PATCH=/mnt/e/ubuntu/projects/r36max2/patches/aic8800-7.2.8-compat.patch
OUT72=/root/r36/out72
AA=/mnt/e/ubuntu/artifacts/aic72
T=/tmp/aic72

echo "=== [0] remove the mis-staged 6.12 modules from the 7.2.8 tree ==="
for m in aic8800_fdrv aic_load_fw; do
  f="$OUT72/lib/modules/7.2.8/extra/$m.ko"
  if [ -e "$f" ]; then
    v=$(modinfo -F vermagic "$f" 2>/dev/null | awk '{print $1}')
    if [ "$v" != "7.2.8" ]; then echo "  deleting $m.ko (vermagic $v)"; rm -f "$f"; fi
  fi
done

echo "=== [1] clean source copy ==="
rm -rf "$T"; mkdir -p "$T"
cp -a "$AIC"/. "$T"/
find "$T" \( -name '*.o' -o -name '*.ko' -o -name '*.mod' -o -name '*.mod.c' \
     -o -name '.*.cmd' -o -name 'Module.symvers' -o -name 'modules.order' \) -delete
echo "  copied $(find "$T" -name '*.c' | wc -l) .c files"

echo "=== [2] apply the 7.2.8 compat patch ==="
(cd "$T" && patch -p1 --dry-run -s -d drivers -i "$PATCH" >/dev/null 2>&1 && \
            patch -p1 -s -d drivers -i "$PATCH" && echo "  applied cleanly") || \
  echo "  !! dry run failed - the tree is already patched or diverged"
grep -c "wireless_dev \*wdev" "$T"/drivers/aic8800/aic8800_fdrv/rwnx_main.c | sed 's/^/  wdev callbacks in rwnx_main.c: /'
grep -c "strscpy" "$T"/drivers/aic8800/aic8800_fdrv/rwnx_msg_tx.c | sed 's/^/  strscpy in rwnx_msg_tx.c: /'
grep -c "in_hardirq" "$T"/drivers/aic8800/aic8800_fdrv/rwnx_rx.c | sed 's/^/  in_hardirq in rwnx_rx.c: /'

echo
echo "=== [3] build against 7.2.8 ==="
make -C "$T/drivers/aic8800" KDIR="$K7" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j8 \
  > /tmp/aic72b.log 2>&1
echo "  exit=$? errors=$(grep -c 'error:' /tmp/aic72b.log) warnings=$(grep -c 'warning:' /tmp/aic72b.log)"
grep -E "error:" /tmp/aic72b.log | head -6 | sed 's/^/    /'
tail -3 /tmp/aic72b.log | sed 's/^/    /'

echo
echo "=== [4] stage + verify vermagic ==="
mkdir -p "$AA" "$OUT72/lib/modules/7.2.8/extra"
ok=1
for m in aic8800_fdrv aic_load_fw; do
  f=$(find "$T" -name "$m.ko" 2>/dev/null | head -1)
  if [ -z "$f" ]; then echo "  !! $m.ko missing"; ok=0; continue; fi
  v=$(modinfo -F vermagic "$f" | awk '{print $1}')
  echo "  $m: $(stat -c%s "$f") B vermagic=$v sha=$(sha256sum "$f" | cut -c1-16)"
  [ "$v" = "7.2.8" ] || { echo "    !! wrong kernel, not staged"; ok=0; continue; }
  cp -f "$f" "$AA/$m-7.2.8.ko"
  cp -f "$f" "$OUT72/lib/modules/7.2.8/extra/$m.ko"
done
echo "  7.2.8 extra dir:"
for f in "$OUT72"/lib/modules/7.2.8/extra/*.ko; do
  echo "    $(basename "$f") $(stat -c%s "$f") B vermagic=$(modinfo -F vermagic "$f" | awk '{print $1}') $(sha256sum "$f" | cut -c1-16)"
done

echo
echo "=== [5] same bytes as the card that is passing WiFi traffic right now? ==="
timeout 60 sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV 'for f in /lib/modules/7.2.8/extra/aic*.ko; do echo "  card $(basename $f) $(stat -c%s $f) B $(sha256sum $f | cut -c1-16)"; done; echo "  wifi is up: $(ip -br addr show wlan0 | tr -s " ")"' 2>&1 | tail -6
[ "$ok" = 1 ] && echo "=== aic72 staged OK ===" || echo "=== aic72 staging INCOMPLETE ==="
