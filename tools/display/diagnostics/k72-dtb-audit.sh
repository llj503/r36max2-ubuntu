#!/bin/bash
# k72-dtb-audit.sh - the device did not come back on the network after we
# replaced the dtb with the rumble-polarity build.  Before blaming the dtb,
# prove what actually changed in it.
set -uo pipefail

echo "=== every 7.2.8 / 6.12 dtb on disk, newest first ==="
find /root/r36 -name 'rk3326-xifan-r36max2*.dtb' -printf '%T@ %s %p\n' 2>/dev/null |
  sort -rn | awk '{printf "  %s  %8d  %s\n", strftime("%m-%d %H:%M",$1), $2, $3}'

echo
echo "=== sha256 (the two hashes that matter: dc775a67 = booted OK, bc2854c9 = what we deployed) ==="
for f in $(find /root/r36 -name 'rk3326-xifan-r36max2*.dtb' 2>/dev/null | sort); do
  printf "  %s  %8d  %s\n" "$(sha256sum "$f" | cut -c1-8)" "$(stat -c%s "$f")" "$f"
done

echo
echo "=== decompile the deployed 7.2.8 dtb and the 6.12 gpuopp dtb ==="
D=/tmp/dtb-audit; rm -rf $D; mkdir -p $D
NEW=$(find /root/r36/linux-7.2.8 -name 'rk3326-xifan-r36max2.dtb' | head -1)
OLD=""
for cand in "$D/none"; do :; done
# recover the pre-fix build if a copy of it survived anywhere
for p in /root/r36/out72/boot /root/r36/out72 /root/r36/k72-stage; do
  c=$(find "$p" -maxdepth 2 -name '*7.2.8*.dtb' 2>/dev/null | head -1)
  [ -n "$c" ] && OLD="$c" && break
done
echo "  NEW = ${NEW:-MISSING}"
echo "  OLD(pre-fix) = ${OLD:-not preserved anywhere}"
[ -n "$NEW" ] && dtc -I dtb -O dts "$NEW" > $D/new.dts 2>/dev/null && echo "  decompiled new: $(wc -l < $D/new.dts) lines"
[ -n "$OLD" ] && dtc -I dtb -O dts "$OLD" > $D/old.dts 2>/dev/null && echo "  decompiled old: $(wc -l < $D/old.dts) lines"
if [ -n "$NEW" ] && [ -n "$OLD" ]; then
  echo "  --- diff old -> new (should be ONLY the rumble-gpio flags) ---"
  diff $D/old.dts $D/new.dts | sed 's/^/      /' || true
fi

echo
echo "=== the nodes that could break boot: chosen/simple-framebuffer/panel/regulators ==="
grep -nE 'rumble-gpio|compatible = "rocknix,generic-dsi"|compatible = "xifan|status = "disabled"' $D/new.dts 2>/dev/null | sed 's/^/  /'

echo
echo "=== does the 7.2.8 Image that boots still sit next to it? ==="
for p in /root/r36/linux-7.2.8/arch/arm64/boot/Image /root/r36/out72/Image-7.2.8; do
  [ -e "$p" ] && printf "  %s  %10d  %s\n" "$(sha256sum "$p" | cut -c1-8)" "$(stat -c%s "$p")" "$p"
done
echo "=== audit done ==="
