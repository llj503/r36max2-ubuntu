# SPDX-License-Identifier: GPL-2.0-or-later
# r36-status-screen: on-screen state page, redrawn every 30s from the FAT
# partition mounted read-only at /mnt/boot. Shares that mountpoint with
# r36-bootlog and r36-wifi-setup on purpose (kernel refuses a second mount of
# one block device when the RO state would change - fixed in v20, see
# WIFI-AND-SHARING.md).

PKG_NAME="status-screen"
PKG_VERSION="1.0"
PKG_LICENSE="GPL-2.0-or-later"
PKG_SITE="https://github.com/llj503/r36max2-ubuntu"
PKG_URL=""
PKG_DEPENDS_TARGET="rootfs-apt"
PKG_LONGDESC="fb0-drawn status page (IP, WiFi, load, boot log tail)."
PKG_TOOLCHAIN="manual"

make_target() {
  :
}

makeinstall_target() {
  install -m 755 ${PKG_DIR}/r36-status-screen ${INSTALL}/usr/local/sbin/r36-status-screen
  install -m 644 ${PKG_DIR}/r36-status-screen.service ${INSTALL}/usr/lib/systemd/system/
  enable_service r36-status-screen.service
}
