# SPDX-License-Identifier: GPL-2.0-or-later
# libretro-parallel-n64: libretro core for Nintendo 64 (paraLLEl's mupen64plus fork).
#
# ARCH must be passed. The Makefile defaults it to `uname -m` on the build host and feeds it
# straight into WITH_DYNAREC, so without it an aarch64 target gets the x86-64 dynarec - the
# same trap as flycast's platform=unix, and it fails at link or, worse, at run time.
# With ARCH=aarch64 it selects WITH_DYNAREC=aarch64, which is the JIT this board can use.
#
# HAVE_PARALLEL / HAVE_PARALLEL_RSP stay 0: those pull in the Vulkan path and the parallel
# RSP assembler (the tree ships a debug-toolchain for it). Neither is needed for the OpenGL
# renderers, and .gitmodules in this archive is empty, so everything else is vendored.
#
# CC_AS defaults to $(CC) here, so unlike flycast the assembler is already the compiler
# driver and needs no override.

PKG_NAME="libretro-parallel-n64"
PKG_VERSION="862071a8b786224905a763e8b15bdcaf75739341"
PKG_SHA256="2be4fd8492ae7c2f1f3b28038fca5a11a36d034d976e8673733c05754a4318db"
PKG_LICENSE="GPL-2.0-or-later"
PKG_SITE="https://github.com/libretro/parallel-n64"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Libretro core: Nintendo 64."
PKG_TOOLCHAIN="manual"

make_target() {
  cd ${PKG_BUILD} && make -f Makefile platform=unix ARCH=aarch64 \
    CC="${CC}" CXX="${CXX}" \
    HAVE_PARALLEL=0 HAVE_PARALLEL_RSP=0
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/lib/libretro
  [ -f ${PKG_BUILD}/parallel_n64_libretro.so ] ||
    die "libretro-parallel-n64: build produced no parallel_n64_libretro.so"
  install -m 644 ${PKG_BUILD}/parallel_n64_libretro.so ${INSTALL}/usr/lib/libretro/
}
