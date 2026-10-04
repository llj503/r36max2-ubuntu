#!/bin/bash
# v20-aic72.sh - the 7.2.8 WiFi modules are not in the paths build-rootfs.sh
# assumes, so rebuild them from the radxa-pkg source + our compat patch (that is
# the reproducible route), stage them, and then prove byte-identity against the
# exact files the running card is using for WiFi right now.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
K7=/root/r36/linux-7.2.8
OUT72=/root/r36/out72
PATCH=/mnt/e/ubuntu/projects/r36max2/patches/aic8800-7.2.8-compat.patch
AA=/mnt/e/ubuntu/artifacts/aic72
CANDIDATES="/root/r36/aic8800-radxa/src/USB/driver_fw /root/r36/aic8800/src/USB/driver_fw /root/r36/wifi/drivers/aic8800 /root/r36/aic-src/src/USB/driver_fw"

AIC=""
for c in $CANDIDATES; do
  [ -d "$c/drivers/aic8800" ] && { AIC="$c"; break; }
  [ -d "$c" ] && ls "$c" 2>/dev/null | grep -q aic8800 && { AIC="$c"; break; }
done
echo "  AIC source tree: ${AIC:-NOT FOUND}"
[ -n "$AIC" ] || { echo "!! no aic8800 tree found; searching deeper"; find /root/r36 -maxdepth 4 -name "aic8800_fdrv" -type d 2>/dev/null | sed 's/^/    /'; exit 1; }

echo "=== [1] kernel release of that tree + patch state ==="
REL=$(cat "$AIC/include/config/kernel.release" 2>/dev/null || echo none)
echo "  built-against: $REL"
echo "  patch file   : $(wc -l < "$PATCH") lines"
echo "  applies cleanly (dry run against a fresh copy)?"
rm -rf /tmp/aicchk; mkdir -p /tmp/aicchk
cp -a "$AIC" /tmp/aicchk/tree 2>/dev/null
(cd /tmp/aicchk/tree && patch -p1 --dry-run -s -i "$PATCH" 2>&1 | head -5) || echo "    (already applied or conflicts - checking symbols instead)"
grep -c "wdev" "$AIC"/drivers/aic8800/aic8800_fdrv/*.c 2>/dev/null | grep -v ":0" | head -4 | sed 's/^/    wdev mentions in /'

echo
echo "=== [2] build for 7.2.8 ==="
mkdir -p "$AA"
make -C "$AIC/drivers/aic8800" KDIR="$K7" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j8 \
  > /tmp/aic72-build.log 2>&1
rc=$?
echo "  exit=$rc errors=$(grep -c 'error:' /tmp/aic72-build.log) warnings=$(grep -c 'warning:' /tmp/aic72-build.log)"
grep -E "error:" /tmp/aic72-build.log | head -5 | sed 's/^/    /'
find "$AIC" -name "*.ko" -printf "  %-28s %8s B  %p\n" 2>/dev/null | head -6

echo
echo "=== [3] stage them ==="
for m in aic8800_fdrv aic_load_fw; do
  f=$(find "$AIC" -name "$m.ko" 2>/dev/null | head -1)
  if [ -n "$f" ]; then
    cp -f "$f" "$AA/$m-7.2.8.ko"
    cp -f "$f" "$OUT72/lib/modules/7.2.8/extra/$m.ko"
    echo "  $m: $(stat -c%s "$f") B  vermagic=$(modinfo -F vermagic "$f" | head -1)"
  else
    echo "  !! $m.ko not produced"
  fi
done
echo "  extra dir now:"
for f in "$OUT72"/lib/modules/7.2.8/extra/*.ko; do
  echo "    $(basename "$f") $(stat -c%s "$f") B  $(sha256sum "$f" | cut -c1-16)"
done

echo
echo "=== [4] compare with what the running card uses for WiFi right now ==="
timeout 60 sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV 'for f in /lib/modules/7.2.8/extra/*.ko; do echo "  card $(basename $f) $(stat -c%s $f) B $(sha256sum $f | cut -c1-16)"; done' 2>&1 | tail -8
echo "=== aic staging done ==="
