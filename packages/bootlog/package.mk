# SPDX-License-Identifier: GPL-2.0-or-later
# r36-bootlog: periodic full-state report to BOOT:\r36-boot.txt - the board's
# black-box flight recorder (no UART on this hardware).

PKG_NAME="r36-bootlog"
PKG_VERSION="1.0"
PKG_LICENSE="GPL-2.0-or-later"
PKG_SITE="https://github.com/llj503/r36max2-ubuntu"
PKG_URL=""
PKG_DEPENDS_TARGET="rootfs-apt"
PKG_LONGDESC="Writes the full device state to the BOOT partition every 2 minutes."
PKG_TOOLCHAIN="manual"

make_target() {
  :
}

makeinstall_target() {
  install -m 755 ${PKG_DIR}/r36-bootlog ${INSTALL}/usr/local/sbin/r36-bootlog
  install -m 644 ${PKG_DIR}/r36-bootlog.service ${INSTALL}/etc/systemd/system/
  install -m 644 ${PKG_DIR}/r36-bootlog.timer ${INSTALL}/etc/systemd/system/
  enable_service r36-bootlog.timer
}
