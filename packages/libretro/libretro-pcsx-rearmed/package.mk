# SPDX-License-Identifier: GPL-2.0-or-later
# libretro-pcsx-rearmed: libretro core for PlayStation.
#
# Same shape as libretro-fceumm, and the same measured build command:
#   make -f Makefile.libretro platform=unix CC=<cross> CXX=<cross>
#   -> pcsx_rearmed_libretro.so, ELF64 / AArch64, install into /usr/lib/libretro
# platform=unix, not platform=linux / linux-aarch64: those tokens are unknown to these
# Makefiles and fall through to the Windows branch, which links a .dll without -fPIC
# and dies on R_AARCH64_ADR_PREL_PG_HI21 relocations.
# Pin the commit and hash the commit URL - GitHub embeds the top directory name in the
# tarball, so the branch URL hashes differently for the same tree.

PKG_NAME="libretro-pcsx-rearmed"
PKG_VERSION="c8816799b50388e61cfe237fe2cdbb7d8175f20a"
PKG_SHA256="edeb21fdeef8815521cb9d4488d2cd35746607c968ca9b26cce4e42c09f2dc99"
PKG_LICENSE="GPL-2.0"
PKG_SITE="https://github.com/libretro/pcsx_rearmed"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Libretro core: PlayStation."
PKG_TOOLCHAIN="manual"

make_target() {
  # cd is not decoration. This tree ships a ./configure, so the framework gives it an
  # out-of-tree build directory and runs make_target() inside
  # ${PKG_BUILD}/.aarch64-r36max2-linux-gnu - which is empty, so "-f Makefile.libretro"
  # died with "No such file or directory" while the same command by hand in
  # ${PKG_BUILD} built fine. fceumm never hit this because it has no configure.
  cd ${PKG_BUILD} && make -f Makefile.libretro platform=unix CC="${CC}" CXX="${CXX}"
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/lib/libretro
  [ -f ${PKG_BUILD}/pcsx_rearmed_libretro.so ] ||
    die "libretro-pcsx-rearmed: build produced no pcsx_rearmed_libretro.so"
  install -m 644 ${PKG_BUILD}/pcsx_rearmed_libretro.so ${INSTALL}/usr/lib/libretro/
}
