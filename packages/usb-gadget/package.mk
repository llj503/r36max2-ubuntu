# SPDX-License-Identifier: GPL-2.0-or-later
# r36-usb-gadget: USB gadget role for the dwc2 controller (ssh over the
# Type-C cable when no WiFi is configured).

PKG_NAME="usb-gadget"
PKG_VERSION="1.0"
PKG_LICENSE="GPL-2.0-or-later"
PKG_SITE="https://github.com/llj503/r36max2-ubuntu"
PKG_URL=""
PKG_DEPENDS_TARGET="rootfs-apt"
PKG_LONGDESC="Configures the dwc2 USB gadget (usb0 @ 192.168.7.2)."
PKG_TOOLCHAIN="manual"

make_target() {
  :
}

makeinstall_target() {
  install -m 755 ${PKG_DIR}/r36-usb-gadget ${INSTALL}/usr/local/sbin/r36-usb-gadget
  install -m 644 ${PKG_DIR}/r36-usb-gadget.service ${INSTALL}/usr/lib/systemd/system/
  enable_service r36-usb-gadget.service
}
