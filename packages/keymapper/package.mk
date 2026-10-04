# SPDX-License-Identifier: GPL-2.0-or-later
# r36-keymapper: uinput joypad-to-mouse/keyboard bridge (opt-in: started by
# weston.service via WantedBy=weston.service, never enabled at boot) and
# r36-hostkeys, the first-boot SSH host key generator that lets the image ship
# with zero baked-in host keys.

PKG_NAME="r36-keymapper"
PKG_VERSION="1.0"
PKG_LICENSE="GPL-2.0-or-later"
PKG_SITE="https://github.com/llj503/r36max2-ubuntu"
PKG_URL=""
PKG_DEPENDS_TARGET="rootfs-apt"
PKG_LONGDESC="Joypad->mouse/keyboard uinput bridge + first-boot SSH host key gen."
PKG_TOOLCHAIN="manual"

make_target() {
  :
}

makeinstall_target() {
  install -m 755 ${PKG_DIR}/r36-keymapper.py ${INSTALL}/usr/local/bin/r36-keymapper.py
  install -m 644 ${PKG_DIR}/r36-keymapper.service ${INSTALL}/etc/systemd/system/
  install -m 644 ${PKG_DIR}/r36-hostkeys.service ${INSTALL}/etc/systemd/system/
  enable_service r36-hostkeys.service

  # sshd must not start before host keys exist (v20-hostkeys.py logic)
  mkdir -p ${INSTALL}/etc/systemd/system/ssh.service.d
  cat > ${INSTALL}/etc/systemd/system/ssh.service.d/r36-hostkeys.conf <<'EOF'
[Unit]
# the image ships with no SSH host keys; r36-hostkeys generates them on
# first boot (ssh-keygen -A). Without this drop-in sshd fails to start.
Requires=r36-hostkeys.service
After=r36-hostkeys.service
EOF

  # nothing baked in: scrub anything the ubuntu base or apt preseeded
  rm -f ${INSTALL}/etc/ssh/ssh_host_* 2>/dev/null || true
}
