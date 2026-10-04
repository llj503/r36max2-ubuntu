# SPDX-License-Identifier: GPL-2.0-or-later
# gpu-demos: the EGL/GLES2 proof-of-stack programs, cross-compiled from the
# repo sources (v20 shipped prebuilt binaries from an untracked dir).
# Its mesa/drm headers come from the multiarch sysroot that the apt layer
# re-mirrors - see make_target.

PKG_NAME="gpu-demos"
PKG_VERSION="1.0"
PKG_LICENSE="GPL-2.0-or-later"
PKG_SITE="https://github.com/llj503/r36max2-ubuntu"
PKG_URL=""
PKG_DEPENDS_TARGET="rootfs-apt"
PKG_LONGDESC="r36-gles2-demo + egl-probe: headless EGL/GLES2 stack verification."
PKG_TOOLCHAIN="make"

unpack() {
  # scripts/unpack only enters its UNPACK block when ${SOURCES}/${PKG_NAME} or
  # ${PKG_DIR}/sources exists or the package defines unpack() itself - a lone
  # post_unpack() is never reached, and it left an empty build dir here: with no
  # download there is nothing to gate on.  (A sources/ dir is not an option:
  # .gitignore's bare `sources/` rule swallows it, which is what hid the vendored
  # panel driver.)  PKG_BUILD still points into the private unpack dir and does
  # not exist yet at this point, hence the mkdir.
  mkdir -p ${PKG_BUILD}
  cp -f ${PKG_DIR}/Makefile ${PKG_DIR}/*.c ${PKG_BUILD}/
}

make_target() {
  # deliberately no -I / -L here.  the cross gcc has this sysroot compiled in
  # (gcc -print-sysroot), and reaching the same headers through a path *outside*
  # it makes ld treat Ubuntu's libc.so linker script as a native one: its
  # GROUP / AS_NEEDED entries are absolute, so they stop being re-rooted and the
  # link dies on "cannot find /usr/lib/aarch64-linux-gnu/libc.so.6".  CC, CFLAGS
  # and LDFLAGS already arrive from config/functions.
  make r36-gles2-demo egl-probe
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/local/bin
    install -m 755 ${PKG_BUILD}/r36-gles2-demo ${INSTALL}/usr/local/bin/r36-gles2-demo
    install -m 755 ${PKG_BUILD}/egl-probe ${INSTALL}/usr/local/bin/egl-probe
  mkdir -p ${INSTALL}/usr/local/share/r36-gpu
    install -m 644 ${PKG_DIR}/r36-gles2-demo.c ${PKG_DIR}/egl-probe.c ${INSTALL}/usr/local/share/r36-gpu/
  install -m 644 ${PKG_DIR}/Makefile ${INSTALL}/usr/local/share/r36-gpu/Makefile
}
