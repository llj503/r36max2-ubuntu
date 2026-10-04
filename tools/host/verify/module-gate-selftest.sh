#!/bin/bash
# module-gate-selftest.sh - run scripts/v20-rootfs.sh against a fake staging rootfs
# and a fake out72, to prove the module gate works: only one kernel tree (7.2.8),
# only the manifest-checked .ko, no build/source symlinks, and it stops on a tampered
# prebuilt or a wrong vermagic.  The tamper cases work on a COPY of the store (PREBUILT
# is an input to the script), so the real artifacts/prebuilt bytes are never touched.
#
#   bash tools/host/verify/module-gate-selftest.sh
set -u
REPO=${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}
cd "$REPO" || exit 1
W=$(mktemp -d)
cleanup() { umount -f "$W/rootfs/proc" 2>/dev/null; rm -rf "$W"; }
trap cleanup EXIT
fail=0
note() { echo "  $*"; }

PB="$W/prebuilt"
cp -a artifacts/prebuilt "$PB"
M72="$W/out72/lib/modules/7.2.8"
mkdir -p "$M72/kernel/net/wireless" "$M72/extra" "$W/out/boot" \
         "$W/rootfs"/{proc,sys,dev,lib} "$W/rootfs/lib/modules" "$W/rootfs/etc/modules-load.d"
printf 'obj-m\n' > "$M72/modules.order"
cp "$PB/aic8800_fdrv.ko" "$M72/kernel/net/wireless/cfg80211.ko"
# an .ko the build tree happens to carry in extra/: it must NOT survive into the rootfs
printf 'BOGUS-UNSIGNED\n' > "$M72/extra/some-leftover.ko"
ln -sfn /nonexistent "$M72/build"
ln -sfn /nonexistent "$M72/source"
echo "rocknix_singleadc_joypad" > "$W/rootfs/etc/modules-load.d/r36max2.conf"
mkdir -p "$W/rootfs/usr/sbin"
# [5] reads the staged dtbs, so give it something to look at (invalid dtb content is
# fine: dtc output is discarded, only existence is asserted there)
touch "$W/out/boot/rk3326-xifan-r36max2.dtb" "$W/out/boot/rk3326-xifan-r36max2-usbhost.dtb"

run() { R="$W/rootfs" OUT="$W/out" OUT72="$W/out72" PREBUILT="$PB" \
        bash scripts/v20-rootfs.sh > "$W/run.log" 2>&1; echo $?; }

echo "=== A. clean inputs ==="
rc=$(run); note "rc=$rc"
grep -E '^  ok |^  !! |stray|vermagic=' "$W/run.log" | sed 's/^/    /' | head -12
[ "$rc" = 0 ] || { note "FAIL  clean run did not complete"; fail=1; tail -25 "$W/run.log" | sed 's/^/      /'; }
echo "  extra/ contents: $(ls "$W/rootfs/lib/modules/7.2.8/extra" 2>/dev/null | tr '\n' ' ')"
for m in aic8800_fdrv aic_load_fw rocknix-singleadc-joypad rocknix-joypad; do
  [ -e "$W/rootfs/lib/modules/7.2.8/extra/$m.ko" ] || { note "FAIL  $m.ko missing"; fail=1; }
done
[ -e "$W/rootfs/lib/modules/7.2.8/extra/some-leftover.ko" ] \
  && { note "FAIL  the build tree's stray .ko survived"; fail=1; } \
  || note "ok      stray extra/*.ko from out72 was dropped"
for l in build source; do
  [ -e "$W/rootfs/lib/modules/7.2.8/$l" ] && { note "FAIL  $l symlink survived"; fail=1; }
done
note "module trees in the fake rootfs: $(ls "$W/rootfs/lib/modules" | tr '\n' ' ')"
sha_real=$(sha256sum artifacts/prebuilt/aic_load_fw.ko | cut -c1-12)

echo "=== B. a second kernel tree in the rootfs is refused ==="
mkdir -p "$W/rootfs/lib/modules/6.12.79/extra"
rc=$(run); note "rc=$rc"
[ "$rc" = 0 ] && { note "FAIL  two kernel trees accepted"; fail=1; } || note "ok      two kernel trees refused"
grep -q 'a second kernel tree survived' "$W/run.log" || { note "FAIL  did not say why"; fail=1; }
rm -rf "$W/rootfs/lib/modules/6.12.79"

echo "=== C. a tampered copy of the .ko store is refused ==="
printf 'corrupt\n' >> "$PB/aic_load_fw.ko"
rc=$(run); note "rc=$rc"
[ "$rc" = 0 ] && { note "FAIL  tampered .ko accepted"; fail=1; } || note "ok      tampered prebuilt refused"
grep -qE 'MANIFEST|不一致' "$W/run.log" || { note "FAIL  did not say why"; fail=1; }

echo "=== D. a .ko whose vermagic is not 7.2.8 is refused even if its sha matches ==="
cp -f "$REPO"/artifacts/prebuilt/*.ko "$PB/"
# give it a manifest that lies: recompute the sha so only the vermagic check can catch it
printf 'not-a-module-for-7.2.8\n' > "$PB/rocknix-joypad.ko"
( cd "$PB" && for f in *.ko; do printf '%s *%s\n' "$(sha256sum "$f" | cut -d' ' -f1)" "$f"; done > MANIFEST.sha256 )
rc=$(run); note "rc=$rc"
[ "$rc" = 0 ] && { note "FAIL  wrong-vermagic .ko accepted"; fail=1; } || note "ok      wrong vermagic refused despite a matching manifest"
grep -q 'vermagic' "$W/run.log" || { note "FAIL  did not say why"; fail=1; }

echo "=== the real store is untouched ==="
[ "$(sha256sum artifacts/prebuilt/aic_load_fw.ko | cut -c1-12)" = "$sha_real" ] \
  && note "ok      artifacts/prebuilt/aic_load_fw.ko still $sha_real" \
  || { note "FAIL  the real store changed"; fail=1; }
git status --short -- artifacts 2>/dev/null | sed 's/^/  git: /'

echo "=== module-gate-selftest: $([ "$fail" = 0 ] && echo ALL PASS || echo FAILURES) ==="
exit "$fail"
