# SPDX-License-Identifier: GPL-2.0-or-later
# libretro-fceumm: NES/Famicom core (libretro port of FCEUmm).
#
# First core in this tree, and the one used to settle the build pattern for all of
# them. Measured here, not copied from a doc:
#   make -f Makefile.libretro platform=unix CC=<cross>
#     -> fceumm_libretro.so, 4779552 bytes, ELF64 / AArch64 / DYN
#        NEEDED: libm.so.6, libc.so.6 only; highest GLIBC symbol 2.38
#        46 exported retro_* entry points
#   platform=linux-aarch64 is NOT a token this Makefile knows: it falls through to the
#   win branch, links a .dll, and dies with "relocation R_AARCH64_ADR_PREL_PG_HI21 ...
#   dangerous relocation" because that branch never adds -fPIC. platform=linux has the
#   same problem. Use platform=unix and nothing else.
#
# Cores are not in the Ubuntu archive (resolute has retroarch 1.22.2 but "No such
# package" for libretro), so each one is built here and installed flat into
# /usr/lib/libretro, where es_systems.cfg points RetroArch with -L.

PKG_NAME="libretro-fceumm"
PKG_VERSION="7a542dab1e87679921962a9f056186eca425c0c2"
# Pin the commit, never refs/heads/<branch>: GitHub's archive tarball embeds the top
# directory name, so the same commit hashes differently by URL form. Measured here -
# archive/refs/heads/master.tar.gz is c992d909..., archive/<sha>.tar.gz is f80b5c1d...
# for the identical tree. The first build of this recipe died on exactly that
# (10 retries, "Incorrect checksum calculated on downloaded file").
PKG_SHA256="f80b5c1df39e22d78791b1867ea79f3ec8c0823e4b1f82b3f89e432c614a6c53"
PKG_LICENSE="GPL-2.0"
PKG_SITE="https://github.com/libretro/libretro-fceumm"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Libretro NES/Famicom core (FCEUmm)."
PKG_TOOLCHAIN="manual"

make_target() {
  # No CFLAGS/CXXFLAGS on purpose: a core's own Makefile.libretro picks its
  # optimisation, and the framework's hardening/pic flags land on files compiled
  # without -fPIC in the same rule, which is what broke the first attempt here.
  cd ${PKG_BUILD} && make -f Makefile.libretro platform=unix CC="${CC}" CXX="${CXX}"
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/lib/libretro
  [ -f ${PKG_BUILD}/fceumm_libretro.so ] ||
    die "libretro-fceumm: build produced no fceumm_libretro.so"
  install -m 644 ${PKG_BUILD}/fceumm_libretro.so ${INSTALL}/usr/lib/libretro/
}
