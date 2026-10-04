# SPDX-License-Identifier: GPL-2.0-or-later
# r36-expand-root: online root partition expansion (2 GiB image -> full card),
# no reboot.

PKG_NAME="r36-expand-root"
PKG_VERSION="1.0"
PKG_LICENSE="GPL-2.0-or-later"
PKG_SITE="https://github.com/llj503/r36max2-ubuntu"
PKG_URL=""
PKG_DEPENDS_TARGET="rootfs-apt"
PKG_LONGDESC="Grows the root partition + filesystem to fill the card on first boot."
PKG_TOOLCHAIN="manual"

make_target() {
  :
}

makeinstall_target() {
  install -m 755 ${PKG_DIR}/r36-expand-root ${INSTALL}/usr/local/sbin/r36-expand-root
  install -m 755 ${PKG_DIR}/r36-finish-expand ${INSTALL}/usr/local/sbin/r36-finish-expand
  install -m 644 ${PKG_DIR}/r36-resize-root.service ${INSTALL}/etc/systemd/system/
  enable_service r36-resize-root.service
}
