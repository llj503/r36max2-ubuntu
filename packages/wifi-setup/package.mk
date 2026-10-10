# SPDX-License-Identifier: GPL-2.0-or-later
# r36-wifi-setup: the BOOT:\wifi.txt configuration channel. This board has no
# keyboard, no UART and no host-mode USB, so a text file on the FAT partition
# is the only practical input channel; results come back as wifi-status.txt.

PKG_NAME="wifi-setup"
PKG_VERSION="1.0"
PKG_LICENSE="GPL-2.0-or-later"
PKG_SITE="https://github.com/llj503/r36max2-ubuntu"
PKG_URL=""
PKG_DEPENDS_TARGET="rootfs-apt"
PKG_LONGDESC="Applies BOOT:\\wifi.txt to wpa_supplicant, writes wifi-status.txt back."
PKG_TOOLCHAIN="manual"

make_target() {
  :
}

makeinstall_target() {
  install -m 755 ${PKG_DIR}/r36-wifi-setup ${INSTALL}/usr/local/sbin/r36-wifi-setup
  install -m 644 ${PKG_DIR}/r36-wifi-setup.service ${INSTALL}/usr/lib/systemd/system/
  install -m 644 ${PKG_DIR}/r36-wifi-setup.timer ${INSTALL}/usr/lib/systemd/system/
  install -m 644 ${PKG_DIR}/r36-wpa@.service ${INSTALL}/usr/lib/systemd/system/
  enable_service r36-wifi-setup.service
  enable_service r36-wifi-setup.timer
  # the instantiated instance is what multi-user pulls in
  mkdir -p ${INSTALL}/etc/systemd/system/multi-user.target.wants
    ln -sf /usr/lib/systemd/system/r36-wpa@.service \
      ${INSTALL}/etc/systemd/system/multi-user.target.wants/r36-wpa@wlan0.service

  # ES's Wi-Fi menu.  The directory is not a style choice: ApiSystem::
  # isScriptingSupported(ApiSystem::WIFI) tests the literal path "/usr/bin/" + "wifictl",
  # so anywhere else and the menu entry is never added, however well the script works.
  # See packages/wifi-setup/wifictl for the subcommand contract it implements.
  # The mkdir is load-bearing: scripts/build:472-475 pre-creates /usr/local/bin,
  # /usr/local/sbin and the two systemd directories - not /usr/bin - and GNU install
  # makes no directories, so the first run died on "cannot create .../usr/bin/wifictl".
  mkdir -p ${INSTALL}/usr/bin
  install -m 755 ${PKG_DIR}/wifictl ${INSTALL}/usr/bin/wifictl
}
