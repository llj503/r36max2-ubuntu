# SPDX-License-Identifier: GPL-2.0-or-later
# libretro-vba-next: libretro core for GBA (Game Boy Advance).
#
# Same shape as libretro-fceumm, and the same measured build command:
#   make -f Makefile.libretro platform=unix CC=<cross> CXX=<cross>
#   -> vba_next_libretro.so, ELF64 / AArch64, install into /usr/lib/libretro
# platform=unix, not platform=linux / linux-aarch64: those tokens are unknown to these
# Makefiles and fall through to the Windows branch, which links a .dll without -fPIC
# and dies on R_AARCH64_ADR_PREL_PG_HI21 relocations.
# Pin the commit and hash the commit URL - GitHub embeds the top directory name in the
# tarball, so the branch URL hashes differently for the same tree.

PKG_NAME="libretro-vba-next"
PKG_VERSION="788192f215ad0a1413f1625b40ebba3423fa0ade"
PKG_SHA256="e97c5839474183ba4b05db212b6c7b09ef7e0bfba3a2cab2ed8ebe34abe8339d"
PKG_LICENSE="GPL-2.0"
PKG_SITE="https://github.com/libretro/vba-next"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Libretro core: GBA (Game Boy Advance)."
PKG_TOOLCHAIN="manual"

make_target() {
  make -f Makefile.libretro platform=unix CC="${CC}" CXX="${CXX}"
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/lib/libretro
  [ -f ${PKG_BUILD}/vba_next_libretro.so ] ||
    die "libretro-vba-next: build produced no vba_next_libretro.so"
  install -m 644 ${PKG_BUILD}/vba_next_libretro.so ${INSTALL}/usr/lib/libretro/
}
