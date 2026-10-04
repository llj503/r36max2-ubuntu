#!/bin/bash
# Build mainline 6.12.79 for the XiFan R36 Max 2: Image + dtbs + modules,
# then the two out-of-tree modules (rocknix joypad, AIC8800DC WiFi).
set -u
REPO=${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
K=${K:-/root/r36/linux-6.12.79}
OUT=${OUT:-/root/r36/out}
X=ARCH=arm64
CROSS=CROSS_COMPILE=aarch64-linux-gnu-
JOYPAD=/root/r36/joypad/src
# The WiFi driver that actually works on this board is the radxa-pkg bundle: it
# is the one that knows chip_sub_id==2 (h_u02) and uploads
# fmacfw_patch_8800dc_h_u02.bin.  The older aic8800dc-linux-patched-main tree
# *compiles* against new kernels but fails at runtime (SCANU command timeout,
# then a jump through a garbage pointer in cmd_mgr_msgind) - do not use it.
AIC=${AIC:-/root/r36/aic8800-radxa/src/USB/driver_fw}
AIC_PATCH7=$REPO/projects/r36max2/patches/aic8800-7.2.8-compat.patch
KREL=$(cat "$K/include/config/kernel.release" 2>/dev/null || echo unknown)
JP=$REPO/build/joypad

mkdir -p "$OUT"
cd "$K" || exit 1

echo "=== [1/6] sync config (INPUT_POLLDEV now available) ==="
make $X $CROSS olddefconfig >/dev/null 2>&1
grep -E "^(CONFIG_INPUT_POLLDEV|CONFIG_JOYSTICK_ODROIDGO2|CONFIG_JOYSTICK_RGB20S|CONFIG_MEMCG|CONFIG_CGROUP_PIDS|CONFIG_CGROUP_BPF|CONFIG_PSI|CONFIG_DRM_PANFROST|CONFIG_MMC_DW_ROCKCHIP|CONFIG_EXT4_FS)=" .config | sort

echo "=== [2/6] build Image + dtbs + modules ==="
make $X $CROSS -j"$(nproc)" Image dtbs modules 2>&1 | tail -25
[ -f arch/arm64/boot/Image ] || { echo "FATAL: no Image"; exit 1; }

echo "=== [3/6] install modules ==="
make $X $CROSS INSTALL_MOD_PATH="$OUT" modules_install >/dev/null 2>&1
KVER=$(make kernelversion)
echo "kernel version: $KVER"
ls "$OUT/lib/modules/" 2>&1

echo "=== [4/6] build rocknix joypad (external) ==="
echo "    The last patch converts the driver to the gpiod consumer API, which is"
echo "    what lets the SAME source build on 6.12 and on 7.x (the integer GPIO API"
echo "    and of_gpio.h are gone in 7.x).  That conversion ties the module to the"
echo "    DT polarity flags in projects/r36max2/dt/rk3326-xifan-r36max2.dts:"
echo "      amux-a/amux-b ACTIVE_HIGH (address bits: logical == physical),"
echo "      amux-en       ACTIVE_LOW  and the driver ASSERTS it to connect the mux,"
echo "      rumble-gpio   ACTIVE_HIGH (measured: pad high spins the motor),"
echo "      every button  as declared - gpiod reads them logically, so the legacy"
echo "      active_level comparison is preserved."
echo "    Building this patch set against an unconverted board dtb gives a module"
echo "    that loads, registers input nodes and then reports nothing."
cd "$JOYPAD" || exit 1
for p in "$JP"/001-legacy-kernel-platform-remove-returns-int.patch \
         "$JP"/003-export-joypad-input-g-and-vfs-ns.patch \
         "$JP"/0001-add-xifan-device-vibrator.patch \
         "$JP"/0002-add-vibration.patch \
         $REPO/projects/r36max2/patches/joypad-gpiod.patch; do
  [ -f "$p" ] || continue
  if patch -p1 --dry-run -s -i "$p" >/dev/null 2>&1; then
    patch -p1 -s -i "$p" >/dev/null 2>&1 && echo "patched: $(basename "$p")"
  else
    echo "already-applied/skipped: $(basename "$p")"
  fi
done
make -C "$K" M="$JOYPAD" $X $CROSS DEVICE=RK3326 modules 2>&1 | tail -12
find "$JOYPAD" -name "*.ko" -printf "%f\n" 2>/dev/null

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
make -C drivers/aic8800 KDIR="$K" $X $CROSS modules 2>&1 | tail -15
find "$AIC" -name "*.ko" -printf "%f %s\n" 2>/dev/null

echo "=== [6/6] stage artifacts ==="
mkdir -p "$OUT/boot"
cp -v arch/arm64/boot/Image "$OUT/boot/"
cp -v arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dtb "$OUT/boot/" 2>&1
mkdir -p "$OUT/firmware"
cp -rf "$AIC/fw/aic8800DC" "$OUT/firmware/" 2>&1 | tail -2
du -sh "$OUT" 2>/dev/null
echo "=== BUILD SCRIPT DONE ==="
