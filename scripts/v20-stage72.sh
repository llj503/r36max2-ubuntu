#!/bin/bash
# v20-stage72.sh - collect the kernel-side artifacts into one place so the image
# build has a single source: Image + the three board dtbs in out/boot.
#
# One kernel since v21: this used to also fetch the 6.12.79 dtb and copy four
# out-of-tree .ko into the module tree.  The .ko now arrive through
# scripts/v20-rootfs.sh, which refuses to stage anything whose sha256 does not
# match artifacts/prebuilt/MANIFEST.sha256 - staging an unchecked copy here first
# only gave the pipeline a second thing to get wrong.
set -uo pipefail
REPO=${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
K7=${K7:-/root/r36/linux-7.2.8}
OUT=${OUT:-/root/r36/out}
OUT72=${OUT72:-/root/r36/out72}

echo "=== [1] kernel + dtbs ==="
mkdir -p "$OUT/boot"
echo "  Image  sha: $(sha256sum "$K7/arch/arm64/boot/Image" | cut -c1-16)"
cp -f "$K7/arch/arm64/boot/Image" "$OUT/boot/Image"
for d in rk3326-xifan-r36max2 rk3326-xifan-r36max2-usbhost rk3326-xifan-r36max2-gadget; do
  cp -f "$K7/arch/arm64/boot/dts/rockchip/$d.dtb" "$OUT/boot/$d.dtb"
  echo "  $d.dtb sha: $(sha256sum "$OUT/boot/$d.dtb" | cut -c1-16)"
done
ls -l "$OUT/boot" | sed 's/^/  /'
# The gpio flags are the thing that was wrong on hardware (rumble and the amp enable
# line inverted), so read them back out of the compiled dtb rather than trusting a
# recorded hash - the dts is the source of truth, the flags are the assertion.
echo "  want: amux-a-gpios flag 0x00, amux-en-gpios flag 0x01, rumble-gpio flag 0x00"
dtc -I dtb -O dts "$OUT/boot/rk3326-xifan-r36max2.dtb" 2>/dev/null |
  grep -E "amux-a-gpios|amux-en-gpios|rumble-gpio" | sed 's/^/    /'

echo
echo "=== [2] the 7.2.8 modules tree the rootfs step will consume ==="
du -sh "$OUT72/lib/modules/7.2.8" 2>/dev/null | sed 's/^/  /'
echo "  .ko in it: $(find "$OUT72/lib/modules/7.2.8" -name '*.ko' 2>/dev/null | wc -l)"
echo "  extra/ here is ignored by v20-rootfs.sh (it installs the manifest-checked .ko)"

echo
echo "=== [3] the four out-of-tree .ko, from the verified store only ==="
PREBUILT=${PREBUILT:-$REPO/artifacts/prebuilt}
if [ -s "$PREBUILT/MANIFEST.sha256" ]; then
  ( cd "$PREBUILT" && sha256sum -c --quiet MANIFEST.sha256 ) \
    && echo "  artifacts/prebuilt verifies clean:" \
    || echo "  !! artifacts/prebuilt does NOT match its manifest - v20-rootfs.sh will refuse to build"
  while read -r _ n; do
    n=${n#\*}
    echo "    $n vermagic=$(modinfo -F vermagic "$PREBUILT/$n" 2>/dev/null | awk '{print $1}')"
  done < "$PREBUILT/MANIFEST.sha256"
else
  echo "  !! $PREBUILT/MANIFEST.sha256 missing - the .ko have not been staged yet"
fi
echo "=== staging done ==="
