# SPDX-License-Identifier: GPL-2.0-or-later
# libretro-fbneoplus: arcade core, FinalBurn Neo "Plus" fork.
#
# Why this one: the board had no arcade core at all, and this is the only one of the
# requested five that is a plain source build with no external library beyond libc/libm.
#
# Pinned to the same commit the reference distribution pins (8ebb4eea...), so the two
# trees can be compared if a game behaves differently; the repo's HEAD has moved on
# (e681da7d).  Tarball rather than git, like every other core here: PKG_SHA256 is
# measured on the downloaded archive, and GitHub's archive of a commit is stable.
#
# platform=aarch64 is the Makefile's own branch (src/burner/libretro/Makefile:70), and
# it is deliberately NOT platform=unix: the unix branch is chosen by probing the BUILD
# host, which here is an x86-64 machine, and would select the x86 dynarec for an
# aarch64 target.  The aarch64 branch sets USE_CYCLONE=0 and HAVE_NEON=0 by itself -
# Cyclone is a 32-bit ARM JIT, so neither applies; that is also why the reference
# recipe's explicit `USE_CYCLONE=0 profile=performance` is not copied, it is redundant
# on this branch.  Verified rather than assumed by grepping the branch above.
#
# The core's output is named fbneo_libretro.so even in this fork.  It is installed as
# fbneoplus_libretro.so so it cannot be confused with (or silently replaced by) a
# mainline fbneo drop-in, and es_systems.cfg's <core> name matches the file.

PKG_NAME="libretro-fbneoplus"
PKG_VERSION="8ebb4eea9dd7d84d150efb46c264600319a70108"
PKG_SHA256="ee0dace4241f543750fc85571b1a40c7994d7b6485209f90691260b35144d76b"
PKG_LICENSE="Non-commercial"
PKG_SITE="https://github.com/lrf739146825/FBNeo"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Libretro arcade core, FinalBurn Neo Plus fork."
PKG_TOOLCHAIN="make"

make_target() {
  # cd first, like every other core recipe here: make_target does not run inside
  # ${PKG_BUILD}, which the first attempt proved with "src/burner/libretro: No such file
  # or directory" while the directory plainly exists in the tarball.
  cd ${PKG_BUILD} && make -C src/burner/libretro platform=aarch64 CC="${CC}" CXX="${CXX}" AR="${AR}"
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/lib/libretro
  local SO=${PKG_BUILD}/src/burner/libretro/fbneo_libretro.so
  # "it produced a file" is not "it produced a core": a link failure that leaves a stale
  # object behind would otherwise install silently, so check the architecture too.
  [ -f "${SO}" ] || die "libretro-fbneoplus: no fbneo_libretro.so built"
  file "${SO}" | grep -q 'ARM aarch64' ||
    die "libretro-fbneoplus: ${SO} is not an aarch64 shared object - the wrong platform branch was built"
  install -m 644 "${SO}" ${INSTALL}/usr/lib/libretro/fbneoplus_libretro.so
}
