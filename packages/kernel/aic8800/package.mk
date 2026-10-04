# SPDX-License-Identifier: GPL-2.0-or-later
# aic8800: AIC8800DC USB WiFi out-of-tree driver (radxa-pkg tree).
#
# Pinned at the newest radxa tag - the 7.2.8 cfg80211 compat patch
# (patches/aic8800-7.2.8-compat.patch, hardware-verified on this board in v20)
# applies cleanly here; it does NOT apply to the 4.x tags.
# Firmware ships separately (aic8800-dc-fw): radxa dropped the 8800DC .bin
# files from this tree after 4.x.

PKG_NAME="aic8800"
PKG_VERSION="5.0+git20260123.5f7be68d-9"
PKG_SHA256="416f587eab1f7ce083d44991245158f7a602b21aed778b39b195b74c14a6609e"
PKG_LICENSE="GPL"
PKG_SITE="https://github.com/radxa-pkg/aic8800"
PKG_URL="${PKG_SITE}/archive/refs/tags/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain linux"
PKG_LONGDESC="AIC8800 USB WiFi driver (aic8800_fdrv + aic_load_fw) for the R36 Max 2."
PKG_TOOLCHAIN="manual"

post_patch() {
  # the compat patch was generated against src/USB/driver_fw/drivers - apply it
  # there, exactly like v20-aic72b.sh did
  patch -s -p1 -d ${PKG_BUILD}/src/USB/driver_fw/drivers \
    < ${PKG_DIR}/aic8800-7.2.8-compat.patch ||
    die "aic8800: 7.x compat patch failed to apply"
}

pre_make_target() {
  unset LDFLAGS
}

make_target() {
  kernel_make -C ${PKG_BUILD}/src/USB/driver_fw/drivers/aic8800 \
    KDIR=$(get_build_dir linux) modules
}

makeinstall_target() {
  local KVER="$(get_pkg_variable linux PKG_VERSION)"
  mkdir -p ${INSTALL}/lib/modules/${KVER}/extra
    cp ${PKG_BUILD}/src/USB/driver_fw/drivers/aic8800/aic8800_fdrv/aic8800_fdrv.ko \
       ${PKG_BUILD}/src/USB/driver_fw/drivers/aic8800/aic_load_fw/aic_load_fw.ko \
       ${INSTALL}/lib/modules/${KVER}/extra/
}
