# SPDX-License-Identifier: GPL-2.0-or-later
# libretro-gpsp-ezode: GBA core, gameplaySP "mod for rumble and ezode" (lcdyk0517/gpsp-mod).
#
# Built from source for this tree rather than copied like the reference distro does:
# its recipe's aarch64 branch does not compile anything, it `cp`s
# gpsp_ezode_32b_libretro.so out of a PARALLEL 32-BIT build tree
# (${ROOT}/build.${DISTRO}-${DEVICE}.arm/install_pkg/...), and its own platform patch
# adds a branch compiled with `-marm` / `CPU_ARCH := arm`.  A 32-bit .so cannot be
# loaded by this image's aarch64 RetroArch, so copying it would install a file that is
# guaranteed to fail at load time.
#
# platform=arm64 is the Makefile's own branch (Makefile:380-388: TARGET=gpsp_libretro.so,
# CPU_ARCH := arm64, HAVE_DYNAREC := 1, MMAP_JIT_CACHE = 1, -fPIC, --no-undefined with
# the link.T version script).
#
# platform=unix is a trap, and this is why the branch was read line by line. That path
# never asks what the CROSS-compiler is: Makefile:23-34 decides the JIT from
# `$(shell uname -a)` of the BUILD HOST, so on this x86-64 WSL box it sets
# CPU_ARCH := x86_32 and adds x86/x86_stub.S to SOURCES_ASM - the aarch64 gas then has to
# assemble x86 opcode mnemonics. The only automatic arm64 JIT route is Makefile:61-69,
# gated on the literal string "webos" appearing inside CROSS_COMPILE, which our toolchain
# name does not contain. Either way `unix` is wrong here; arm64 is the branch that means it.
#
# Why bother when gba already has two cores: this one carries the rumble/edge feature set
# the user asked for by name, and it is the only one of the five that is a genuine
# aarch64 JIT build of a modded core.

PKG_NAME="libretro-gpsp-ezode"
PKG_VERSION="b4918c367e1954c9f1f795da7f8a5a6fc8e2d5e5"
PKG_SHA256="d28db1d5a69072636c6a88ffe4d8734aac7368f157f67d4b3f6374b298dd0074"
PKG_LICENSE="GPL-2.0"
PKG_SITE="https://github.com/lcdyk0517/gpsp-mod"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Libretro GBA core: gameplaySP mod with rumble support, built for aarch64."
PKG_TOOLCHAIN="make"

make_target() {
  cd ${PKG_BUILD} && make platform=arm64 CC="${CC}" CXX="${CXX}"
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/lib/libretro
  local SO=${PKG_BUILD}/gpsp_libretro.so
  [ -f "${SO}" ] || die "libretro-gpsp-ezode: no gpsp_libretro.so built"
  file "${SO}" | grep -q 'ARM aarch64' ||
    die "libretro-gpsp-ezode: not an aarch64 object - the platform branch did not take"

  # The JIT is the whole reason this core is here, so prove it was compiled in instead of
  # trusting the Makefile branch: with HAVE_DYNAREC off the object still builds, is still
  # aarch64, and is just slow - nothing about the build would notice.
  #
  # Measured instrument, not a guessed symbol name: Makefile.common:35-44 appends exactly
  # $(CORE_DIR)/arm/arm64_stub.S to SOURCES_ASM when CPU_ARCH=arm64 (the 32-bit path
  # appends arm_stub.S, the interpreter appends neither), and Makefile:584 turns
  # SOURCES_ASM into <dir>/<name>.o next to the source. So the presence of that one object
  # is the build's own record of which branch ran.
  #
  # Symbols are unusable here: link.T exports only retro_* and everything else is local,
  # and the installed copy is stripped by the framework.
  local JITOBJ
  JITOBJ=$(find ${PKG_BUILD} -name 'arm64_stub.o' -print -quit 2>/dev/null)
  [ -n "${JITOBJ}" ] ||
    die "libretro-gpsp-ezode: no arm/arm64_stub.o - built interpreter-only, which is not what this core is for"
  if find ${PKG_BUILD} -name 'arm_stub.o' -print -quit 2>/dev/null | grep -q .; then
    die "libretro-gpsp-ezode: arm_stub.o (the 32-bit ARM JIT) was built - wrong CPU_ARCH"
  fi
  build_msg "CLR_OK" "STEP" "arm64 dynarec object: ${JITOBJ#${PKG_BUILD}/}" "indent"

  install -m 644 "${SO}" ${INSTALL}/usr/lib/libretro/gpsp_ezode_libretro.so
}
