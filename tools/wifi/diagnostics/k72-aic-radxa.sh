#!/bin/bash
# k72-aic-radxa.sh - the 7.2.8 WiFi crash was almost certainly self-inflicted:
# I built the modules from /root/r36/wifi/aic8800dc-linux-patched-main (46 .c
# files, 631 KB fdrv.ko) while the working 6.12 image ships the radxa-pkg
# bundle build (971 KB fdrv.ko, the tree that actually knows chip_sub_id==2 /
# h_u02).  Build the SAME source the working system uses, against 7.2.8.
set -uo pipefail
K=/root/r36/linux-7.2.8
R=/root/r36/aic8800-radxa/src/USB/driver_fw
T=/root/r36/k72aic
X=ARCH=arm64
CROSS=CROSS_COMPILE=aarch64-linux-gnu-

echo "=== source tree ==="
ls "$R" 2>/dev/null | sed 's/^/  /' | head -6
grep -c . /dev/null
echo "  fdrv .c count: $(find "$R/drivers/aic8800" -name '*.c' | wc -l)"

echo "=== clean copy so we never touch the 6.12 build ==="
rm -rf "$T"; mkdir -p "$T"
cp -r "$R/drivers" "$T/" 2>/dev/null
cp -r "$R/fw" "$T/" 2>/dev/null

echo "=== build against 7.2.8 ==="
cd "$T/drivers/aic8800" || exit 1
make clean >/dev/null 2>&1
make -C "$T/drivers/aic8800" KDIR="$K" $X $CROSS 2>&1 | \
  grep -E "error:|warning: implicit|undefined|ERROR|\.ko|LD|CC \[M\]" | tail -25
echo "=== produced ==="
find "$T" -name "*.ko" -printf "  %p  %s bytes\n"
echo "=== compare with what the working card runs ==="
echo "  6.12 image fdrv : $(stat -c %s /root/r36/rootfs/lib/modules/6.12.79/extra/aic8800_fdrv.ko 2>/dev/null) bytes"
echo "  wrong 7.2 build : $(stat -c %s /root/r36/k72test/wifi/drivers/aic8800/aic8800_fdrv/aic8800_fdrv.ko 2>/dev/null) bytes"
echo "  new   7.2 build : $(find "$T" -name aic8800_fdrv.ko -printf '%s' | head -1) bytes"
echo "=== symbols the new .ko needs (any unknown ones would fail insmod) ==="
new=$(find "$T" -name aic8800_fdrv.ko | head -1)
if [ -n "$new" ]; then
  modprobe -n -S 7.2.8 --show-depends "$new" 2>&1 | head -3 | sed 's/^/  /'
  aarch64-linux-gnu-nm -u "$new" 2>/dev/null | awk '{print $2}' | sort -u > /tmp/need72.txt
  awk '{print $2}' "$K/Module.symvers" | sort -u > /tmp/have72.txt
  echo "  undefined symbols not provided by the kernel: $(comm -23 /tmp/need72.txt /tmp/have72.txt | wc -l)"
  comm -23 /tmp/need72.txt /tmp/have72.txt | head -10 | sed 's/^/    ! /'
fi
echo "=== radxa build done ==="
