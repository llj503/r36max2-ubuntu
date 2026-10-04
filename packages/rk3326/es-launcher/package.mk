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

  # ES reads two filenames and nothing else - es_input.cfg and es_systems.cfg - looked
  # up in ~/.emulationstation first, then /etc/emulationstation.  Installing the
  # hardware-verified map under its repo name (es-input-r36max2.cfg) left it unread, so
  # the device booted into the "press a key to configure your controller" screen with no
  # keyboard attached.  The root copy is what the working card has; the /etc one covers
  # the ubuntu account.
  #
  # es_systems.cfg is not optional: this fork logs "ERROR es_systems.cfg file does not
  # exist!" and exits, and with zero systems no theme is ever looked up, so a fresh
  # image would show nothing to look at either.  Both copies carry this board's SDL GUID
  # and the joystick1left/joystick1up axis bindings (menu navigation only consumes
  # *left/*up names or joystick1* axes; leftanalog* has no consumer in this fork).
  mkdir -p ${INSTALL}/etc/emulationstation ${INSTALL}/root/.emulationstation
  install -m 644 ${PKG_DIR}/es-input-r36max2.cfg ${INSTALL}/etc/emulationstation/es_input.cfg
  install -m 644 ${PKG_DIR}/es-input-matched.cfg ${INSTALL}/etc/emulationstation/es-input-matched.cfg
  install -m 644 ${PKG_DIR}/es_systems.cfg       ${INSTALL}/etc/emulationstation/es_systems.cfg
  cp -f ${INSTALL}/etc/emulationstation/es_input.cfg    ${INSTALL}/root/.emulationstation/es_input.cfg
  cp -f ${INSTALL}/etc/emulationstation/es_systems.cfg  ${INSTALL}/root/.emulationstation/es_systems.cfg
}
