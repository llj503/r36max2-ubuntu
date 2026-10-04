# SPDX-License-Identifier: GPL-2.0-or-later
# r36-wayland: weston session + helper stack. Installed but NOT enabled - the
# 7.2.x VOP can lose vblank under long weston sessions and wedge the CRTC
# (see WAYLAND.md); r36-wayland start / systemctl stop weston is the switch.

PKG_NAME="wayland"
PKG_VERSION="1.0"
PKG_LICENSE="GPL-2.0-or-later"
PKG_SITE="https://github.com/llj503/r36max2-ubuntu"
PKG_URL=""
PKG_DEPENDS_TARGET="rootfs-apt r36-keymapper r36-osk"
PKG_LONGDESC="Weston session (installed-not-enabled) + joypad bridge wiring."
PKG_TOOLCHAIN="manual"

make_target() {
  :
}

makeinstall_target() {
  install -m 755 ${PKG_DIR}/r36-wayland ${INSTALL}/usr/local/bin/r36-wayland
  install -m 644 ${PKG_DIR}/weston.ini ${INSTALL}/etc/xdg/weston/weston.ini
  install -m 644 ${PKG_DIR}/weston.service ${INSTALL}/etc/systemd/system/weston.service
  install -m 644 ${PKG_DIR}/zz-r36-wayland.sh ${INSTALL}/etc/profile.d/zz-r36-wayland.sh

  # the two things that must not regress (apply-wayland.sh checks, kept)
  grep -q 'locking=false' ${INSTALL}/etc/xdg/weston/weston.ini ||
    die "r36-wayland: weston.ini lost locking=false"
  grep -q 'ExecStopPost=.*chvt 1' ${INSTALL}/etc/systemd/system/weston.service ||
    die "r36-wayland: weston.service lost its console restore"
}
