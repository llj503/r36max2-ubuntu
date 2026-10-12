# SPDX-License-Identifier: GPL-2.0-or-later
# onscripter: the ONScripter visual-novel engine, built from the maintained upstream
# YuriSizuku/OnscripterYuri ("onsyuri"). Games are directories of .arc/.nsa/scripts with
# a .ons marker next to them; see sources/r36-ons.
#
# Why this upstream and not the name the request used. "ONScripter-OGRE" has no repository:
# searching GitHub for onscripter-ogre returns total_count=None, and the engine families
# that do exist are ogapee/onscripter (the original, SDL1-era, last pushed 2024-01-22),
# jh10001/ONScripter-Jh, and YuriSizuku/OnscripterYuri (855 stars, pushed 2026-06-23,
# CMake + SDL2, its README lists arm/aarch64 cross-compile and retroarch as supported).
# OnscripterYuri is based on ONScripter-Jh, so it is the same line the prebuilt binaries in
# the reference distro come from - and the reference ships onsyuri_32b_libretro.so in
# console_mod_res, which is this project's own libretro target built 32-bit.
#
# Built as the standalone executable, not as the libretro core, for one measured reason:
# src/onsyuri_libretro compiles SDL2, SDL2_image, SDL2_mixer, SDL_ttf, bzip2 and lua from
# vendored sources (its CMakeLists has add_library(sdl2 STATIC deps/SDL/src/SDL.c ...) and
# .gitmodules lists all six), and a GitHub archive unpacks submodules as empty
# directories - files=0 for every one of deps/SDL, deps/SDL_image, deps/SDL_mixer,
# deps/SDL_ttf, deps/lua. The core would need six more pinned fetches. The standalone path
# (CMakeLists.txt:46-70) uses pkg-config/find_package against the same SDL2 family this
# image already ships, so it needs apt packages instead of a submodule import.
#
# The library names come from that block verbatim: SDL2 (find_package CONFIG - the sysroot
# does have cmake/SDL2/), SDL2_ttf, SDL2_image, SDL2_mixer (pkg_check_modules), libjpeg
# (pkg_check_modules), Lua (find_package MODULE), bz2, dl, pthread.
#
# config_linux also compiles in USE_GLES (CMakeLists.txt:12), which is right for this board
# (Mesa/Panfrost, GLES 3.1 on a Mali-G31 - measured from RetroArch's own log) and is the
# reason libgles-dev being in the rootfs matters here rather than being decorative.
#
# NOT GAME-VERIFIED, stated plainly: I:\寨中寨EE4.7通用游戏包128G has no visual-novel
# content - no nscript.dat, no *.nsa, no *.ons anywhere at depth 2, and the only directory
# whose name suggests it is advision, which is the Matty Adventure Vision handheld. The
# reference distro ships no VN games either; its onscripter system is populated by a
# Scan_for_new_games.ons script the user runs themselves. So this recipe is verified to
# build, to install, to be listed by ES, and to be launched - the "engine starts and shows
# its own no-game error" is as far as it goes until actual games are put on the card.

PKG_NAME="onscripter"
PKG_VERSION="08f744b31cc1907b66a15f0402e62321a131ed81"
PKG_SHA256="7d0b640ba4be57fe46f962fd50ebe1c2ad0d51f954ac8042c556ad51c9764449"
PKG_LICENSE="GPL-2.0"
PKG_SITE="https://github.com/YuriSizuku/OnscripterYuri"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
# rootfs-apt because every library above arrives through the apt closure, and that recipe
# is what mirrors the headers, the .pc files and the cmake config dirs into this sysroot.
PKG_DEPENDS_TARGET="toolchain rootfs-apt"
PKG_LONGDESC="ONScripter visual novel engine (OnscripterYuri), built for aarch64."
PKG_TOOLCHAIN="cmake-make"

# NOT MinSizeRel, even though that is the upstream's own size path (CMakeLists.txt:16-19
# turns on -flto and -s under it): this cross gcc was not built with LTO support, so the
# flag is a hard compiler error, not a slower build. Measured on the first run of this
# recipe - eight .cpp in, then
#   cc1plus: error: LTO support has not been enabled in this configuration
# repeated per translation unit. This is the fourth package here to hit the same wall
# (libretro-mgba's -DBUILD_LTO=OFF, libretro-mednafen-saturn's LTO=0, and the -flto=auto
# that satune's Makefile defaults to) and I still reached for the upstream's recommendation
# first. Release keeps -O3 -DNDEBUG and drops -flto; the -s it also drops is done
# explicitly below with ${STRIP}.
PKG_CMAKE_OPTS_TARGET="-DCMAKE_BUILD_TYPE=Release"

makeinstall_target() {
  local BIN
  BIN=$(find ${PKG_BUILD} -maxdepth 2 -type f -name onsyuri -perm -u+x | head -1)
  [ -n "${BIN}" ] || die "onscripter: cmake built no onsyuri executable"
  file "${BIN}" | grep -q 'ARM aarch64' ||
    die "onscripter: onsyuri is not aarch64: $(file "${BIN}")"

  mkdir -p ${INSTALL}/usr/bin
  install -m 755 "${BIN}" ${INSTALL}/usr/bin/onsyuri
  ${STRIP} ${INSTALL}/usr/bin/onsyuri

  # The marker-to-game wrapper ES calls. Options are the upstream's own, read off
  # onscripter_main.cpp's argument loop: -r/--root <dir> (:370) is the game directory,
  # -fullscreen (:408) and -enc:gbk (:386) - the encoding because the games that exist in
  # this region are GBK-text Chinese releases, and without it the script is mojibake.
  mkdir -p ${INSTALL}/usr/local/bin
  install -m 755 ${PKG_DIR}/sources/r36-ons ${INSTALL}/usr/local/bin/r36-ons

  # Same loader check as openbor-ff, same reason: a NEEDED entry that is not in the rootfs
  # the image ships is a build that succeeds and a device that cannot start the engine.
  # It searches ${BUILD}/image/system and not ${SYSROOT_PREFIX}, because scripts/build:451
  # swaps SYSROOT_PREFIX for an almost-empty per-package private copy immediately before
  # makeinstall - checking against it would flag every soname, libc.so.6 included.
  local ROOTFS=${BUILD}/image/system
  [ -d "${ROOTFS}/usr/lib" ] || die "onscripter: no staged rootfs at ${ROOTFS} - is rootfs-apt built?"
  local soname missing=""
  for soname in $(readelf -d ${INSTALL}/usr/bin/onsyuri 2>/dev/null |
                  sed -n 's/.*Shared library: \[\(.*\)\]/\1/p'); do
    find -L "${ROOTFS}/usr/lib" "${ROOTFS}/lib" -name "${soname}" -print -quit 2>/dev/null |
      grep -q . || missing="${missing} ${soname}"
  done
  if [ -n "${missing}" ]; then
    die "onscripter: links against${missing}, which is not in the staged rootfs"
  fi
  build_msg "CLR_OK" "STEP" "NEEDED all present: $(readelf -d ${INSTALL}/usr/bin/onsyuri 2>/dev/null | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p' | tr '\n' ' ')" "indent"
}
