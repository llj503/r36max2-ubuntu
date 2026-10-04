# SPDX-License-Identifier: GPL-2.0-or-later
# aic8800-dc-fw: firmware for the AIC8800DC USB WiFi (chip_sub_id == 2, the
# h_u02 build - see HARDWARE.md).
#
# radxa removed the 8800DC .bin firmware from their tree after 4.x, so the
# firmware is pinned at the last tag that ships it. Modules are built from the
# 5.0 tag (see packages/kernel/aic8800).

PKG_NAME="aic8800-dc-fw"
PKG_VERSION="4.0+git20250410.b99ca8b6-5"
PKG_SHA256="918cf935a24d211ef56084eb0a0027c0ae13480e88730c2170b67bebfd214966"
PKG_LICENSE="Proprietary (AICSemi)"
PKG_SITE="https://github.com/radxa-pkg/aic8800"
PKG_URL="${PKG_SITE}/archive/refs/tags/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET=""
PKG_LONGDESC="AIC8800DC firmware bundle (fmacfw_patch_8800dc_h_u02.bin set)."
PKG_TOOLCHAIN="manual"

make_target() {
  :
}

makeinstall_target() {
  local FWDIR="${INSTALL}/lib/firmware/aic8800DC"
  mkdir -p "${FWDIR}"
  cp -a ${PKG_BUILD}/src/USB/driver_fw/fw/aic8800DC/. "${FWDIR}/"
}
