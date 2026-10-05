# SPDX-License-Identifier: GPL-2.0-or-later
# r36-expand-root: online root partition expansion (2 GiB image -> full card),
# no reboot.

PKG_NAME="expand-root"
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
  install -m 644 ${PKG_DIR}/r36-resize-root.service ${INSTALL}/usr/lib/systemd/system/
  enable_service r36-resize-root.service
  # Stage 1 needs its own unit: r36-resize-root only finishes the job (it is gated
  # on /var/lib/r36-expand-pending, which stage 1 creates), so shipping just that
  # one left nothing to run r36-expand-root.  Measured on hardware: root stayed at
  # 3.9 GiB of a 58 GiB card and the unit logged "skipped, unmet condition check".
  install -m 644 ${PKG_DIR}/r36-expand-root.service ${INSTALL}/usr/lib/systemd/system/
  enable_service r36-expand-root.service
}
