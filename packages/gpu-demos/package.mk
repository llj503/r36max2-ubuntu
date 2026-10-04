# SPDX-License-Identifier: GPL-2.0-or-later
# gpu-demos: the EGL/GLES2 proof-of-stack programs, cross-compiled from the
# repo sources (v20 shipped prebuilt binaries from an untracked dir).

PKG_NAME="gpu-demos"
PKG_VERSION="1.0"
PKG_LICENSE="GPL-2.0-or-later"
PKG_SITE="https://github.com/llj503/r36max2-ubuntu"
PKG_URL=""
PKG_DEPENDS_TARGET="rootfs-apt"
PKG_LONGDESC="r36-gles2-demo + egl-probe: headless EGL/GLES2 stack verification."
PKG_TOOLCHAIN="make"

# the mesa/drm dev headers live in the image staging tree (installed by the
# apt layer); point the build at them
post_unpack() {
  # scripts/unpack only copies ${PKG_DIR}/sources/, and a directory of that name
  # here would be swallowed by .gitignore's bare `sources/` rule - same trap that
  # hid the vendored panel driver.  The demo sources stay beside package.mk, so
  # bring them into the build dir explicitly (empty PKG_BUILD = "No rule to make
  # target 'r36-gles2-demo'", which is what this package failed with first).
  cp -f ${PKG_DIR}/Makefile ${PKG_DIR}/*.c ${PKG_BUILD}/
}

make_target() {
  local IMGINC="${BUILD}/image/system/usr/include"
  local IMGLIB="${BUILD}/image/system/usr/lib/aarch64-linux-gnu"
  make CC="${CC}" \
    CFLAGS="-O2 -Wall -I${IMGINC} -I${IMGINC}/libdrm" \
    LDFLAGS="-L${IMGLIB}" \
    r36-gles2-demo egl-probe
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/local/bin
    install -m 755 ${PKG_BUILD}/r36-gles2-demo ${INSTALL}/usr/local/bin/r36-gles2-demo
    install -m 755 ${PKG_BUILD}/egl-probe ${INSTALL}/usr/local/bin/egl-probe
  mkdir -p ${INSTALL}/usr/local/share/r36-gpu
    install -m 644 ${PKG_DIR}/r36-gles2-demo.c ${PKG_DIR}/egl-probe.c ${INSTALL}/usr/local/share/r36-gpu/
  install -m 644 ${PKG_DIR}/Makefile ${INSTALL}/usr/local/share/r36-gpu/Makefile
}
