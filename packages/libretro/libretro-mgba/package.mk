# SPDX-License-Identifier: GPL-2.0-or-later
# libretro-mgba: GBA core (mgba), built with CMake.
#
# This one is not the Makefile.libretro shape the other cores in this directory use:
# mgba is CMake, and the core is only produced when BUILD_LIBRETRO is on.
#
# Two flags are load-bearing, both found by failing first:
#   -DBUILD_LTO=OFF  - the cross toolchain here has no LTO, and every translation unit
#       died with "cc1: error: LTO support has not been enabled in this configuration".
#       mgba's own switch is BUILD_LTO (CMakeLists.txt:186); passing
#       CMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF does not touch it.
#   -DSKIP_LIBRARY=on - build the core only, not libmgba.
#
# Verified here: rc=0, mgba_libretro.so out of the CMake build directory.
#
# The build directory is created explicitly rather than inherited from the framework,
# because the framework runs make_target() inside ${PKG_BUILD}/<triple>/ for trees it
# recognises as out-of-tree, and depending on which one you land in is how the
# pcsx_rearmed recipe failed once already.

PKG_NAME="libretro-mgba"
PKG_VERSION="7a12d6d4b9acb14c0ae62c9166b6a2f3d08007f6"
PKG_SHA256="5cbf639e527fb586bf33e14d59037eab35f78f45154e0b79c784fff474c3bc37"
PKG_LICENSE="MPL-2.0"
PKG_SITE="https://github.com/libretro/mgba"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Libretro core: Game Boy Advance (mgba)."
PKG_TOOLCHAIN="manual"

make_target() {
  mkdir -p ${PKG_BUILD}/build-libretro
  cd ${PKG_BUILD}/build-libretro && \
  cmake -DCMAKE_TOOLCHAIN_FILE="${CMAKE_CONF:-${TOOLCHAIN}/etc/cmake-${TARGET_NAME}.conf}" \
        -DBUILD_LIBRETRO=on \
        -DSKIP_LIBRARY=on \
        -DBUILD_LTO=OFF \
        -DBUILD_PGO=OFF \
        -DCMAKE_BUILD_TYPE=Release .. && \
  make -j${CONCURRENCY_MAKE_LEVEL}
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/lib/libretro
  local so="${PKG_BUILD}/build-libretro/mgba_libretro.so"
  [ -f "${so}" ] || so=$(find ${PKG_BUILD} -name 'mgba_libretro.so' | head -1)
  [ -n "${so}" ] && [ -f "${so}" ] ||
    die "libretro-mgba: build produced no mgba_libretro.so"
  install -m 644 "${so}" ${INSTALL}/usr/lib/libretro/
}
