# SPDX-License-Identifier: GPL-2.0-or-later
# libretro-gambatte: libretro core for Game Boy / Game Boy Color.
#
# Same build shape as the other cores in this directory and cross-built here before
# being written down:
#   cd ${PKG_BUILD} && make -f Makefile.libretro platform=unix CC=<cross> CXX=<cross>
#     -> gambatte_libretro.so, 4969864 bytes, ELF64 / AArch64
# Pin the commit and hash the commit URL; GitHub embeds the top directory name in the
# tarball, so the branch URL hashes differently for the same tree.

PKG_NAME="libretro-gambatte"
PKG_VERSION="d9d6cd06382d1ced30de34d56d3609452323dab1"
PKG_SHA256="bd39cd38662135d17e221a7fd34baf2908a40065ade16edf2e8d1168b21b921e"
PKG_LICENSE="GPL-2.0"
PKG_SITE="https://github.com/libretro/gambatte-libretro"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Libretro core: Game Boy / Game Boy Color."
PKG_TOOLCHAIN="manual"

make_target() {
  cd ${PKG_BUILD} && make -f Makefile.libretro platform=unix CC="${CC}" CXX="${CXX}"
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/lib/libretro
  [ -f ${PKG_BUILD}/gambatte_libretro.so ] ||
    die "libretro-gambatte: build produced no gambatte_libretro.so"
  install -m 644 ${PKG_BUILD}/gambatte_libretro.so ${INSTALL}/usr/lib/libretro/
}
