# SPDX-License-Identifier: GPL-2.0-or-later
# r36-osk: uinput on-screen keyboard driven by a wofi grid (opt-in; the only
# way to type on this board without a USB keyboard).

PKG_NAME="osk"
PKG_VERSION="1.0"
PKG_LICENSE="GPL-2.0-or-later"
PKG_SITE="https://github.com/llj503/r36max2-ubuntu"
PKG_URL=""
PKG_DEPENDS_TARGET="rootfs-apt"
PKG_LONGDESC="On-screen keyboard: wofi grid -> uinput key events."
PKG_TOOLCHAIN="manual"

make_target() {
  :
}

makeinstall_target() {
  install -m 755 ${PKG_DIR}/r36-osk.py ${INSTALL}/usr/local/bin/r36-osk
}
