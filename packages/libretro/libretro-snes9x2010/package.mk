# SPDX-License-Identifier: GPL-2.0-or-later
# libretro-snes9x2010: libretro core for SNES (Super Nintendo).
#
# Same shape as libretro-fceumm, and the same measured build command:
#   make -f Makefile.libretro platform=unix CC=<cross> CXX=<cross>
#   -> snes9x2010_libretro.so, ELF64 / AArch64, install into /usr/lib/libretro
# platform=unix, not platform=linux / linux-aarch64: those tokens are unknown to these
# Makefiles and fall through to the Windows branch, which links a .dll without -fPIC
# and dies on R_AARCH64_ADR_PREL_PG_HI21 relocations.
# Pin the commit and hash the commit URL - GitHub embeds the top directory name in the
# tarball, so the branch URL hashes differently for the same tree.

PKG_NAME="libretro-snes9x2010"
PKG_VERSION="fe690dd321fa5a46b5234a2bde089d2518c62b0e"
PKG_SHA256="7d2d2a21c2c00e6c5a83c8b51c18fccb6a9b3764584aa5ceb4b231e3a7c0ab6c"
PKG_LICENSE="GPL-2.0"
PKG_SITE="https://github.com/libretro/snes9x2010"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Libretro core: SNES (Super Nintendo)."
PKG_TOOLCHAIN="manual"

make_target() {
  make -f Makefile.libretro platform=unix CC="${CC}" CXX="${CXX}"
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/lib/libretro
  [ -f ${PKG_BUILD}/snes9x2010_libretro.so ] ||
    die "libretro-snes9x2010: build produced no snes9x2010_libretro.so"
  install -m 644 ${PKG_BUILD}/snes9x2010_libretro.so ${INSTALL}/usr/lib/libretro/
}
