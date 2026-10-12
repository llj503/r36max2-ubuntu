# SPDX-License-Identifier: GPL-2.0-or-later
# openbor-ff: the OpenBOR beat-em-up engine, fork "fflns" (AveyondFly), cross-built for
# this board. Games are .pak files; see packages/emulators/openbor-ff/sources/r36-openbor
# for how a pak is launched.
#
# Built from source, not copied. The reference distro's openbor-ff recipe installs a
# prebuilt binary; this builds the same pinned commit so the engine gets our toolchain,
# our sysroot and our two carried patches, and can be re-verified when SDL2 moves.
#
# The two patches are the point of choosing this fork:
#   0001  SDL input moves to the SDL_GameController API (lands in engine/sdl/control.c,
#         which is where SDL_GameControllerOpen appears). This is why this launcher needs
#         no gptokeyb: the reference distro's OpenBOR variants that lack the patch start
#         a fake keyboard around the engine, and this image does not have gptokeyb.
#   0002  adds the BUILD_LINUX_aarch64 block to engine/Makefile (:125-142).
# Both apply clean at this commit: measured 0 .rej/.orig after patch -p1.
#
# BUILD_LINUX_aarch64 sets BUILD_SDL/GFX/PTHREAD/SDL_IO/VORBIS/WEBM and, importantly, NOT
# BUILD_OPENGL - so this renders through SDL surfaces, not GL. Stated here because it is
# the kind of thing that looks like an oversight: the x86_64 block in the same patch does
# set BUILD_OPENGL + BUILD_LOADGL. Software 2D on a Cortex-A35 is the reference's own
# choice for this board class and is what the .pak games were tested against.
#
# SDKPATH=${SYSROOT_PREFIX} because the aarch64 block turns it into -I/-L:
# INCLUDES=$(SDKPATH)/usr/include,$(SDKPATH)/usr/include/SDL2 (Makefile:137) reaches CFLAGS
# through `INCS += $(INCLUDES)` (:326) and LIBRARIES=$(SDKPATH)/usr/lib reaches the link
# through `LIBS = $(addprefix -L", ...)` (:576 area). Left empty it would be /usr/include
# and /usr/lib - the amd64 host's.
#
# NO_STRIP=1 instead of the reference's sed. Makefile:251 only honours STRIP when
# BUILD_DEBUG/NO_STRIP are unset, and its BUILD_LINUX branch is plain `strip $(TARGET)` -
# the host's amd64 strip, which cannot read an aarch64 ELF. Setting NO_STRIP falls back to
# `STRIP = cp` (:252), and the recipe strips with the cross strip afterwards, so the
# Makefile is not edited to work around a toolchain choice.
#
# PKG_CONFIG_* is deliberately NOT set here. config/functions:218-235 already exports a
# cross pkg-config for target builds - PKG_CONFIG_SYSROOT_DIR=${SYSROOT_PREFIX} and a
# PKG_CONFIG_LIBDIR that globs both usr/lib/<triple>/pkgconfig and lib/<triple>/pkgconfig -
# and engine/Makefile:519 shells out `pkg-config sdl2 --cflags` mid-compile, which is the
# only reason the question came up. Overriding it here would have been narrower than what
# the framework already provides (the measured sdl2.pc lives in lib/aarch64-linux-gnu/, not
# usr/lib/), so the recipe inherits instead of re-declaring.
#
# The tarball is 189 MB because GitHub's archive includes media/; it is fetched once.

PKG_NAME="openbor-ff"
PKG_VERSION="5cac65237db9b1409a0b7ee4a1a64d6507834915"
PKG_SHA256="2e2ff8870a2e177a31ffe7370c18af6ca94f07ba6e8fa15badf12004f9ed4b47"
PKG_LICENSE="Non-commercial"
PKG_SITE="https://github.com/AveyondFly/openbor-fflns"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
# rootfs-apt, not a list of package names: SDL2_gfx and libvpx arrive through the apt
# closure (see packages/rk3326/rootfs-apt), and that recipe is what re-mirrors
# usr/include + usr/lib/aarch64-linux-gnu into this sysroot.
PKG_DEPENDS_TARGET="toolchain rootfs-apt"
PKG_LONGDESC="OpenBOR engine (fflns fork, SDL_GameController input), built for aarch64."
PKG_TOOLCHAIN="make"

post_patch() {
  cd ${PKG_BUILD} || return 1

  # scripts/unpack pipes `patch` through and never checks its exit status, and the build
  # then deletes every .rej, so a patch that silently failed to apply looks identical to
  # one that applied. Assert the content each one introduces instead.
  if ! grep -q 'BUILD_LINUX_aarch64' engine/Makefile; then
    die "openbor-ff: patch 0002 did not apply - no BUILD_LINUX_aarch64 block in engine/Makefile"
  fi
  if ! grep -q 'SDL_GameControllerOpen' engine/sdl/control.c; then
    die "openbor-ff: patch 0001 did not apply - engine/sdl/control.c still has no SDL_GameControllerOpen, which is the input path this fork exists for"
  fi
  # The old joystick API has to be gone, not merely joined by the new one: if both are
  # live the engine reads events twice, which shows up as every button press doing two
  # things and no error anywhere.
  if grep -q 'SDL_JoystickOpen' engine/sdl/control.c; then
    die "openbor-ff: engine/sdl/control.c still calls SDL_JoystickOpen - the 0001 refactor is only half applied"
  fi
}

make_target() {
  cd ${PKG_BUILD}/engine || return 1

  make BUILD_LINUX_aarch64=1 \
       SDKPATH="${SYSROOT_PREFIX}" \
       NO_STRIP=1 \
       CC="${CC}" CXX="${CXX}" AR="${AR}" RANLIB="${RANLIB}"
}

makeinstall_target() {
  cd ${PKG_BUILD}/engine || return 1

  # TARGET=$(VERSION_NAME).elf, TARGET_FINAL=$(VERSION_NAME); with NO_STRIP=1 the second
  # is the cp of the first, so either exists after a successful build. Check the name the
  # engine actually runs with, and its architecture, rather than trusting the build.
  local ELF=${PKG_BUILD}/engine/OpenBOR
  [ -f "${ELF}" ] || die "openbor-ff: no engine/OpenBOR produced (build claimed success)"
  file "${ELF}" | grep -q 'ARM aarch64' ||
    die "openbor-ff: engine/OpenBOR is not aarch64: $(file "${ELF}")"

  mkdir -p ${INSTALL}/usr/bin
  install -m 755 "${ELF}" ${INSTALL}/usr/bin/OpenBOR-ff
  # config/functions:449 exports STRIP="${TARGET_PREFIX}strip" for target builds, so the
  # cross binutils is what runs here - not the host strip the Makefile would have used.
  ${STRIP} ${INSTALL}/usr/bin/OpenBOR-ff

  # The launcher ES calls. It owns the pak-per-launch directory dance OpenBOR requires:
  # sdlport.c:30 hard-codes the game directory as "Paks" relative to the CWD, and
  # menu.c:522 prints "No Mods In Paks Folder!" when it is empty - so the engine cannot be
  # run as "<binary> %ROM%" and needs a wrapper. (Measured CWD names, same grep: Paks, data,
  # screenshots, logs. There is no fonts/language/sprites to ship - that content is inside
  # each .pak, and engine/resources/ turned out to be icons and logos only.)
  mkdir -p ${INSTALL}/usr/local/bin
  install -m 755 ${PKG_DIR}/sources/r36-openbor ${INSTALL}/usr/local/bin/r36-openbor

  # Every library the engine asks the loader for has to be in the rootfs this image ships,
  # not merely have been present at link time: -lvpx and -lSDL2_gfx resolve through a .so
  # symlink whose target is a versioned soname, and if that symlink and the shipped runtime
  # ever disagree, the build still succeeds and the binary dies on the device with
  # "error while loading shared libraries". The sysroot is rootfs-apt's mirror of
  # usr/lib/aarch64-linux-gnu + lib/aarch64-linux-gnu, so checking NEEDED against it is
  # checking against what the card will have.
  local soname missing=""
  for soname in $(readelf -d ${INSTALL}/usr/bin/OpenBOR-ff 2>/dev/null |
                  sed -n 's/.*Shared library: \[\(.*\)\]/\1/p'); do
    find ${SYSROOT_PREFIX} -name "${soname}" -print -quit 2>/dev/null |
      grep -q . || missing="${missing} ${soname}"
  done
  if [ -n "${missing}" ]; then
    die "openbor-ff: links against${missing}, which is not in the mirrored rootfs - the engine would fail to load on the card"
  fi
  build_msg "CLR_OK" "STEP" "NEEDED all present in the shipped rootfs: $(readelf -d ${INSTALL}/usr/bin/OpenBOR-ff 2>/dev/null | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p' | tr '\n' ' ')" "indent"
}
