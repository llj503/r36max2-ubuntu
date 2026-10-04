#!/bin/bash
# Build a mainline kernel for the XiFan R36 Max 2: Image + dtbs + modules, then the
# AIC8800DC WiFi driver, and stage what the packer needs.
#
#   bash scripts/build-all.sh                    # 7.2.8, modules into /root/r36/out72
#   K=/root/r36/linux-7.2.8 OUT=/root/r36/out72 bash scripts/build-all.sh
#
# The out-of-tree .ko built here are not the shipping bytes: the image gets the
# artifacts/prebuilt ones that were proven on the card, verified by sha256 + vermagic
# in scripts/v20-rootfs.sh.  Step [4] exists because that distinction has to be stated
# by a measurement, not by a comment.
set -u
REPO=${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
K=${K:-/root/r36/linux-7.2.8}
OUT=${OUT:-/root/r36/out72}
X=ARCH=arm64
CROSS=CROSS_COMPILE=aarch64-linux-gnu-
# The WiFi driver that actually works on this board is the radxa-pkg bundle: it
# is the one that knows chip_sub_id==2 (h_u02) and uploads
# fmacfw_patch_8800dc_h_u02.bin.  The older aic8800dc-linux-patched-main tree
# *compiles* against new kernels but fails at runtime (SCANU command timeout,
# then a jump through a garbage pointer in cmd_mgr_msgind) - do not use it.
AIC=${AIC:-/root/r36/aic8800-radxa/src/USB/driver_fw}
AIC_PATCH7=$REPO/projects/r36max2/patches/aic8800-7.2.8-compat.patch
JP=$REPO/projects/r36max2/patches
T_JP=$(ls /root/r36/downloads/rocknix-joypad-*.tar.gz 2>/dev/null | head -1)
KREL=$(cat "$K/include/config/kernel.release" 2>/dev/null || echo unknown)
FAILED=""

mkdir -p "$OUT"
cd "$K" || exit 1

echo "=== kernel: $K (kernel.release says $KREL) ==="
echo "=== [1/6] sync config (INPUT_POLLDEV now available) ==="
make $X $CROSS olddefconfig >/dev/null 2>&1
grep -E "^(CONFIG_INPUT_POLLDEV|CONFIG_JOYSTICK_ODROIDGO2|CONFIG_JOYSTICK_RGB20S|CONFIG_MEMCG|CONFIG_CGROUP_PIDS|CONFIG_CGROUP_BPF|CONFIG_PSI|CONFIG_DRM_PANFROST|CONFIG_MMC_DW_ROCKCHIP|CONFIG_EXT4_FS)=" .config | sort

echo "=== [2/6] build Image + dtbs + modules ==="
make $X $CROSS -j"$(nproc)" Image dtbs modules 2>&1 | tail -25
[ -f arch/arm64/boot/Image ] || { echo "FATAL: no Image"; exit 1; }
# the dtb is the other half of the boot: u-boot loads it by name, so a build that
# produced an Image but no board dtb is a black screen, not a partial success
for d in rk3326-xifan-r36max2 rk3326-xifan-r36max2-usbhost rk3326-xifan-r36max2-gadget; do
  [ -f "arch/arm64/boot/dts/rockchip/$d.dtb" ] || { echo "FATAL: no $d.dtb"; exit 1; }
done

echo "=== [3/6] install modules ==="
if ! make $X $CROSS INSTALL_MOD_PATH="$OUT" modules_install >/dev/null 2>&1; then
  echo "!! modules_install failed"; FAILED="$FAILED modules_install"
fi
KVER=$(make kernelversion)
echo "kernel version: $KVER"
echo "  staged: $(ls "$OUT/lib/modules/" 2>/dev/null | tr '\n' ' ')"
[ "$KVER" = "${KREL%%+*}" ] || echo "  !! make kernelversion ($KVER) != kernel.release ($KREL) - dirty tree?"

echo "=== [4/6] the joypad driver: can it be rebuilt here at all? ==="
# Measured 2026-10-04 on a PRISTINE copy of the pinned rev
# (/root/r36/downloads/rocknix-joypad-d02ed13...tar.gz), patches tried in the order
# below - the same order this step uses, which is why the numbers it prints match:
#   001-legacy-kernel-platform-remove-returns-int   1 hunk FAILS
#   0002-add-vibration                              4 hunks FAIL
#   joypad-gpiod                                   10 hunks FAIL
# so this repo's five patches do NOT reproduce the driver the card runs.  The tree that
# /root/r36/joypad/src was left in is half-converted: compiling it against 7.2.8 stops on
# the legacy integer-GPIO calls the vibrator patch adds (gpio_set_value,
# of_get_named_gpio_flags, devm_gpio_request, gpio_direction_output - gone in 7.x, so
# -Werror=implicit-function-declaration).  The image ships artifacts/prebuilt/*.ko
# instead.  This step re-runs the test so the day the patches catch up, that is visible.
PROBE=$OUT/joypad-probe
if [ -n "$T_JP" ] && [ -f "$T_JP" ]; then
  rm -rf "$PROBE"; mkdir -p "$PROBE"
  tar xzf "$T_JP" -C "$PROBE" --strip-components=1 || { echo "  !! cannot extract $T_JP"; FAILED="$FAILED joypad-probe"; }
  (
    cd "$PROBE" || exit 1
    for p in 001-legacy-kernel-platform-remove-returns-int \
             003-export-joypad-input-g-and-vfs-ns \
             0001-add-xifan-device-vibrator 0002-add-vibration joypad-gpiod; do
      [ -f "$JP/$p.patch" ] || { echo "  !! the patch list names $p, which is not in the repo"; exit 1; }
      # -s would summarise "1 out of 7 hunks FAILED" and understate the damage, so
      # count the individual hunk failures verbosely
      bad=$(patch -p1 --dry-run -i "$JP/$p.patch" 2>&1 | grep -c 'Hunk #[0-9]* FAILED')
      if [ "$bad" = 0 ]; then
        patch -p1 -s -i "$JP/$p.patch" >/dev/null 2>&1 && echo "  applies: $p"
      else
        echo "  DOES NOT APPLY ($bad hunk(s)): $p"
      fi
    done
  )
  if make -C "$K" M="$PROBE" $X $CROSS DEVICE=RK3326 modules > "$OUT/joypad-probe.log" 2>&1; then
    echo "  the patched tree BUILDS against $KREL now - diff it against artifacts/prebuilt before trusting it"
    for k in "$PROBE"/*.ko; do
      [ -e "$k" ] || continue
      echo "    $(basename "$k") $(stat -c%s "$k") B vermagic=$(modinfo -F vermagic "$k" | awk '{print $1}')"
    done
  else
    echo "  still does not build against $KREL.  first errors:"
    grep -m4 'error:' "$OUT/joypad-probe.log" | sed 's/^/      /'
    echo "  -> the image keeps shipping artifacts/prebuilt/*.ko (that is the point of the gate)"
  fi
  rm -rf "$PROBE"
else
  echo "  !! no pinned joypad tarball under /root/r36/downloads - the patch set cannot be tested"
  FAILED="$FAILED joypad-probe"
fi

echo "=== [5/6] build AIC8800DC WiFi (external) ==="
cd "$AIC" || exit 1
case "$KREL" in
  7.*)
    if patch -p1 --dry-run -s -d drivers -i "$AIC_PATCH7" >/dev/null 2>&1; then
      patch -p1 -s -d drivers -i "$AIC_PATCH7" && echo "  applied cfg80211 netdev->wdev compat patch (kernel $KREL)"
    else
      echo "  compat patch not applied: either it is already in the tree, or upstream moved again - check by hand"
    fi;;
esac
if make -C drivers/aic8800 KDIR="$K" $X $CROSS modules > "$OUT/aic-build.log" 2>&1; then
  tail -4 "$OUT/aic-build.log"
else
  echo "!! AIC build failed; first errors:"; grep -m6 'error:' "$OUT/aic-build.log" | sed 's/^/      /'
  FAILED="$FAILED aic"
fi
for m in aic8800_fdrv aic_load_fw; do
  k=$(find "$AIC" -name "$m.ko" | head -1)
  [ -n "$k" ] || { echo "  !! no $m.ko produced"; FAILED="$FAILED $m"; continue; }
  v=$(modinfo -F vermagic "$k" | awk '{print $1}')
  echo "  built $m.ko $(stat -c%s "$k") B vermagic=$v"
  [ "$v" = "$KVER" ] || { echo "    !! built for $v, the kernel tree is $KVER"; FAILED="$FAILED $m-vermagic"; }
done

echo "=== [6/6] stage artifacts ==="
# [5] leaves the shell inside the AIC tree, which is why these two copies used to fail
# with "cannot stat arch/arm64/boot/Image" while the Image was there the whole time.
cd "$K" || exit 1
mkdir -p "$OUT/boot" "$OUT/firmware"
cp -v arch/arm64/boot/Image "$OUT/boot/"            || FAILED="$FAILED stage-Image"
cp -v arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dtb "$OUT/boot/" || FAILED="$FAILED stage-dtb"
cp -rf "$AIC/fw/aic8800DC" "$OUT/firmware/" 2>/dev/null || echo "  (no aic firmware dir to stage)"
du -sh "$OUT" 2>/dev/null
if [ -n "$FAILED" ]; then
  echo "=== BUILD INCOMPLETE:$FAILED ==="
  exit 1
fi
echo "=== BUILD SCRIPT DONE ==="
