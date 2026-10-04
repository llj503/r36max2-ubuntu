# SPDX-License-Identifier: GPL-2.0-or-later
# es-launcher: configs and launcher for the batocera-branch
# EmulationStation cross-compiled by the emulationstation package (M5). The
# input configs are the hardware-verified 17-key/4-axis mappings.

PKG_NAME="es-launcher"
PKG_VERSION="1.0"
PKG_LICENSE="GPL-2.0-or-later"
PKG_SITE="https://github.com/llj503/r36max2-ubuntu"
PKG_URL=""
PKG_DEPENDS_TARGET="rootfs-apt"
PKG_LONGDESC="EmulationStation launcher + verified input configs for the R36 Max 2."
PKG_TOOLCHAIN="manual"

make_target() {
  :
}

makeinstall_target() {
  install -m 755 ${PKG_DIR}/r36-es ${INSTALL}/usr/local/bin/r36-es
  mkdir -p ${INSTALL}/etc/emulationstation
    install -m 644 ${PKG_DIR}/es-input-r36max2.cfg ${INSTALL}/etc/emulationstation/es-input-r36max2.cfg
    install -m 644 ${PKG_DIR}/es-input-matched.cfg ${INSTALL}/etc/emulationstation/es-input-matched.cfg
}
