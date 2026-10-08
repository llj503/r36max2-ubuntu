# SPDX-License-Identifier: GPL-2.0-or-later
# libretro-mednafen-saturn: libretro core for Sega Saturn (Mednafen's "satune").
#
# Why this core for Saturn: arkos4clone has no Saturn libretro core at all - it ships
# Yaba Sanshiro as a standalone SDL app under opt/, which would need its own launch path,
# its own config file and its own input mapping. This one is a plain libretro core with
# its deps (libchdr, lzma, zstd) vendored inside the tarball, so it fits the r36-play
# path every other system already uses. Expect it to be slow: satune has no dynarec for
# ARM, so the honest measure is FPS per game, not a claim that Saturn "works".
#
# platform=unix, HAVE_OPENGL=0: the hardware renderer (mednafen_saturn_hw) is a separate
# TARGET_NAME and needs GL headers; the software core is what upstream builds for the
# buildbot and produces mednafen_saturn_libretro.so.
#
# Pin the commit and hash the commit URL - GitHub embeds the top directory name in the
# tarball, so the branch URL hashes differently for the same tree.

PKG_NAME="libretro-mednafen-saturn"
PKG_VERSION="65f05fa66f83e65e33be83aa433d883b4fd9509a"
PKG_SHA256="aadede29d18eae53d4ed69886e17caf7d03ee533b5b1118d4e658c2ffb8a3272"
PKG_LICENSE="GPL-2.0-or-later"
PKG_SITE="https://github.com/libretro/beetle-saturn-libretro"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Libretro core: Sega Saturn (Mednafen satune)."
PKG_TOOLCHAIN="manual"

make_target() {
  cd ${PKG_BUILD} && make -f Makefile platform=unix \
    CC="${CC}" CXX="${CXX}" HAVE_OPENGL=0 HAVE_CHD=1
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/lib/libretro
  [ -f ${PKG_BUILD}/mednafen_saturn_libretro.so ] ||
    die "libretro-mednafen-saturn: build produced no mednafen_saturn_libretro.so"
  install -m 644 ${PKG_BUILD}/mednafen_saturn_libretro.so ${INSTALL}/usr/lib/libretro/
}
