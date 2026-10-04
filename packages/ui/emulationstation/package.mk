# SPDX-License-Identifier: GPL-2.0-or-later
# emulationstation: the ES front end, cross-compiled (v21) instead of built on
# the 1 GB board (v20). Pin = ROCKNIX's emulationstation-next at the exact rev
# + tarball sha256 the v20 workflow verified on the board (es-build.sh, then
# named scripts/k72-esrn.sh).
#
# Notes carried over from EMULATIONSTATION.md (all measured, not guessed):
#   * GLES3 build (-DGLES3=1): the board's GL is 3.1 / GLES 3.1 via panfrost;
#     ES-DE's desktop-GL AppImage does NOT run on it. The v20 board build of
#     the batocera fork completed at -O1/-g0 for one TU; cross-building from
#     the host removes that memory constraint entirely.
#   * gettext is required: without HAVE_INTL, libstdc++ 15's <iomanip> pulls
#     <libintl.h> and collides with ES's fallback ngettext.
#   * the GitHub archive tarball has no submodules: pugixml is fetched
#     separately at the sha pinned in ES's .gitmodules.
#   * the binary lands in the repo root, not build/es-app/ (CMAKE_RUNTIME_
#     OUTPUT_DIRECTORY is overridden upstream).
# Input configs + launcher come from the es-launcher package.

PKG_NAME="emulationstation"
PKG_VERSION="cada856d86e3115fbbf0bce09dd761b0ee8fa9fd"
PKG_SHA256="c92eb0fd6e1e2b5fa603391f6c0b540d4fad858664c23321237df32efecf68ad"
PKG_LICENSE="GPL-2.0"
PKG_SITE="https://github.com/ROCKNIX/emulationstation-next"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
# the theme is not a build input and is not shipped in v21 (decision 2026-10-04), so it
# is not a dependency here either - see packages/virtual/image/package.mk
PKG_DEPENDS_TARGET="toolchain rootfs-apt"
PKG_LONGDESC="EmulationStation front end (emulationstation-next, GLES3), cross-built."
PKG_TOOLCHAIN="cmake-make"

PKG_CMAKE_OPTS_TARGET="-DGLES3=1 \
  -DGL_SYSTEM=1 \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_RULE_MESSAGES=OFF \
  -DCMAKE_VERBOSE_MAKEFILE=OFF"

post_unpack() {
  # A GitHub archive carries no submodule content: external/pugixml unpacks as an
  # empty directory (id3v2lib, libcheevos and nanosvg are real trees), and
  # .gitmodules has no "revision" line to read - the pin lives in the commit's
  # gitlink, which is why this used to die with "cannot read pugixml pin".  The
  # value below came from the tree itself:
  #   git ls-tree ${PKG_VERSION} external/pugixml
  #   -> 160000 commit 61c944895e071872370219cadade8423dc6e04dc external/pugixml
  # and was verified against codeload: 583444 B, sha256 below, with the
  # CMakeLists.txt that external/CMakeLists.txt's add_subdirectory("pugixml")
  # requires (that branch is taken because USE_SYSTEM_PUGIXML defaults to OFF).
  local PUGI_COMMIT="61c944895e071872370219cadade8423dc6e04dc"
  local PUGI_SHA256="d82e28c844f46165bdb2c160466073087888ec81ea87fbe66e3dc7f36aa5c835"
  local TARBALL="${SOURCES}/${PKG_NAME}/pugixml-${PUGI_COMMIT}.tar.gz"

  if [ ! -f "${TARBALL}" ]; then
    mkdir -p "${SOURCES}/${PKG_NAME}"
    curl -fsSL --retry 3 -o "${TARBALL}" \
      "https://codeload.github.com/zeux/pugixml/tar.gz/${PUGI_COMMIT}" ||
      die "emulationstation: cannot fetch pugixml ${PUGI_COMMIT}"
  fi
  echo "${PUGI_SHA256}  ${TARBALL}" | sha256sum -c --status ||
    die "emulationstation: pugixml tarball does not match its pinned sha256"

  mkdir -p ${PKG_BUILD}/external/pugixml
  tar -xzf "${TARBALL}" -C ${PKG_BUILD}/external/pugixml --strip-components=1
  [ -f ${PKG_BUILD}/external/pugixml/CMakeLists.txt ] ||
    die "emulationstation: external/pugixml has no CMakeLists.txt - add_subdirectory would fail"
}

makeinstall_target() {
  # binary is at the repo root (upstream overrides CMAKE_RUNTIME_OUTPUT_DIRECTORY)
  local BIN="${PKG_BUILD}/emulationstation"
  [ -f "${BIN}" ] || BIN="${PKG_BUILD}/es-app/emulationstation"
  [ -f "${BIN}" ] || die "emulationstation: binary not found after build"
  mkdir -p ${INSTALL}/usr/local/bin
    cp "${BIN}" ${INSTALL}/usr/local/bin/emulationstation
}
