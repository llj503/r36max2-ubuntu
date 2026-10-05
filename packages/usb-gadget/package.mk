# SPDX-License-Identifier: GPL-2.0-or-later
# r36-usb-gadget: USB gadget role for the dwc2 controller.
#
# NOT ENABLED, on purpose.  Measured on hardware: the AIC8800DC WiFi module is
# wired to this same OTG controller (it enumerates as usb 1-1 on dwc2), behind an
# analog switch (gpio0_A7) that selects between the module and the Type-C
# connector.  So gadget networking and WiFi are mutually exclusive on this board -
# and with the controller in dr_mode="host" (which WiFi requires) there is no UDC
# at all, so enabling this unit costs a 90 s start timeout before multi-user.target
# is reached, and the boot then reports one permanently failed unit.  Measured
# 2026-10-05 on the flashed v21 image: "Failed to start r36-usb-gadget.service" at
# uptime ~96 s, and the first diagnostic tick of the boot landed at the same 96 s.
#
# To use it: boot the gadget dtb variant (rk3326-xifan-r36max2-gadget.dtb, which
# pins dwc2 to peripheral mode), accept that WiFi is then unavailable, and
# `systemctl enable r36-usb-gadget.service`.

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
  # deliberately not enable_service - see the header
}
