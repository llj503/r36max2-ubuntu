# SPDX-License-Identifier: GPL-2.0-or-later
# r36-fwswap: BOOT-partition switch to the alternate AIC firmware bundle
# (BOOT:\fw\aic8800DC) via the use-boot-fw marker file.

PKG_NAME="fwswap"
PKG_VERSION="1.0"
PKG_LICENSE="GPL-2.0-or-later"
PKG_SITE="https://github.com/llj503/r36max2-ubuntu"
PKG_URL=""
PKG_DEPENDS_TARGET="rootfs-apt"
PKG_LONGDESC="Switches the AIC8800DC firmware search path to the BOOT backup bundle."
PKG_TOOLCHAIN="manual"

make_target() {
  :
}

makeinstall_target() {
  install -m 755 ${PKG_DIR}/r36-fwswap ${INSTALL}/usr/local/sbin/r36-fwswap
  install -m 644 ${PKG_DIR}/r36-fwswap.service ${INSTALL}/usr/lib/systemd/system/
  enable_service r36-fwswap.service
}
