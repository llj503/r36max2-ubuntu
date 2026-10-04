# SPDX-License-Identifier: GPL-2.0-or-later
# rocknix-joypad: the rocknix singleadc joypad driver, gpiod-converted.
#
# Source: AveyondFly/rocknix-joypad at the commit their distro pins.
# Patches (in order): the two historical version-guarded fixes (no-ops on 7.x,
# kept because they document the remove-callback and VFS-namespace history),
# the xifan vibrator additions, then the gpiod conversion.
#
# The gpiod conversion MUST pair with the DT polarity flags in
# projects/RK3326/dt/rk3326-xifan-r36max2.dts: amux-a ACTIVE_HIGH,
# amux-en ACTIVE_LOW driven by logical assert, rumble ACTIVE_HIGH.
# See documentation/PER_DEVICE_DOCUMENTATION/r36max2/KERNELS.md.

PKG_NAME="rocknix-joypad"
PKG_VERSION="7f3272ff6bd002c718291465ae5e5d752ccb24b8"
PKG_SHA256="3f8a48e4be159d5c1ee5018849a9a0d0bdfcfad3797320d7983313b773098d48"
PKG_LICENSE="GPL"
PKG_SITE="https://github.com/AveyondFly/rocknix-joypad"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain linux"
PKG_LONGDESC="ROCKNIX joypad driver (gpiod conversion) for the R36 Max 2."
PKG_TOOLCHAIN="manual"

pre_make_target() {
  unset LDFLAGS
  # the upstream Makefile gates the driver set on DEVICE: without it only
  # rocknix-joypad.ko is built and the singleadc variant this board uses
  # (retrogame_joypad, ADC voltage-ladder keys) is silently skipped
  export DEVICE="RK3326"
}

make_target() {
  kernel_make -C $(get_build_dir linux) M=${PKG_BUILD} modules
}

makeinstall_target() {
  local KVER="$(get_pkg_variable linux PKG_VERSION)"
  mkdir -p ${INSTALL}/lib/modules/${KVER}/extra
    cp *.ko ${INSTALL}/lib/modules/${KVER}/extra/
}
