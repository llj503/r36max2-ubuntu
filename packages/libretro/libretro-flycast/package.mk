# SPDX-License-Identifier: GPL-2.0-or-later
# libretro-flycast: libretro core for Dreamcast (and NAOMI/GD3/Atomiswave).
#
# Chosen over the arkos4clone binaries: those ship flycast2021/2022 as prebuilt
# aarch64 .so, but this builds the same upstream from a pinned commit, so the core
# gets our toolchain and can be re-verified when RetroArch moves.
#
# platform=arm64, not platform=unix. The unix branch runs `uname -m` on the *build host*
# into WITH_DYNAREC and would pick the x86-64 dynarec for an aarch64 target, and it forces
# HAVE_VULKAN=1, which drags in the vendored glslang. The arm64 branch sets
# WITH_DYNAREC=arm64 explicitly, FORCE_GLES=1 (this board is Mesa/Panfrost, GLES 3.1 on a
# Mali-G31 - measured from RetroArch's own log) and leaves Vulkan off.
#
# AS must be the compiler driver: the branch feeds $(CFLAGS) into ASFLAGS, so plain
# `aarch64-...-as` sees -DTARGET_LINUX_ARMv8 and -frename-registers, which it does not
# implement. The Makefile honours AS before falling back to ${CC_PREFIX}as.
#
# HAVE_OPENMP=0: nothing in the sysroot provides libgomp, and the Makefile links with
# -Wl,--no-undefined, so an OpenMP reference is a hard link error rather than a warning.
#
# MFLAGS is where -mno-outline-atomics has to go. This Makefile assigns CFLAGS := of its
# own, so the framework's CFLAGS (which carry that option, and are why the other cores
# link) never reach it; the core then called __aarch64_swp4_acq_rel / __aarch64_ldadd4_acq_rel
# and died, because the sysroot has libatomic.so.1 but no linker name for -latomic.
# MFLAGS is the only flag variable this Makefile leaves alone on the arm64 path (only the
# x86 branches append to it) and the compile rule interpolates it into both the C and the
# C++ command. Cortex-A35 has LL/SC exclusives, so inlined atomics are correct, just not LSE.
#
# CHD needs no extra dependency: HAVE_CHD=1 compiles libretro-common's clean-room rchd
# reader, and that directory is committed inside core/libretro-common of this tarball.

PKG_NAME="libretro-flycast"
PKG_VERSION="4e3e28239d2f224f92c511f95fe2bf3c2bf1454b"
PKG_SHA256="6098ca4443f4dad3f170e1fc8195a2f1219ec2222ab3957814cdf92dc2611b24"
PKG_LICENSE="GPL-2.0-or-later"
PKG_SITE="https://github.com/libretro/flycast"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Libretro core: Dreamcast / NAOMI."
PKG_TOOLCHAIN="manual"

make_target() {
  cd ${PKG_BUILD} && make -f Makefile platform=arm64 \
    CC="${CC}" CXX="${CXX}" AS="${CC}" MFLAGS="-mno-outline-atomics" \
    HAVE_OPENMP=0 HAVE_VULKAN=0 HAVE_CHD=1
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/lib/libretro
  [ -f ${PKG_BUILD}/flycast_libretro.so ] ||
    die "libretro-flycast: build produced no flycast_libretro.so"
  install -m 644 ${PKG_BUILD}/flycast_libretro.so ${INSTALL}/usr/lib/libretro/
}
