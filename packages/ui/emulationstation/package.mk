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

# -DGLES3=1 is real (options declared: GLES/GLES2/GLES3/GL) and cmake then reports
# "Found OpenGLES3 ... libGLESv2.so".  -DGL_SYSTEM=1 was NOT: cmake warned
# "Manually-specified variables were not used by the project: GL_SYSTEM", so it is
# dropped rather than carried on as decoration.  CEC defaults to ON while the probe
# says "Package 'libcec', required by 'virtual:world', not found" - this is an
# RK3326 handheld with no HDMI, so turn it off instead of shipping a phantom
# dependency.  FriBidi is absent too, and ES falls back to its own RTL reordering.
PKG_CMAKE_OPTS_TARGET="-DGLES3=1 \
  -DCEC=OFF \
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

  # resources/ must ship next to the binary.  This tree is not optional and is not
  # the theme: ResourceManager probes ~/.emulationstation/resources, the data dir,
  # the executable's own directory and the cwd, and fonts/help icons/flags resolve
  # only from it.  Shipping just the ELF - what this recipe used to do - produced a
  # binary that ran without crashing and drew nothing: 3429 of 3438 log lines on the
  # board were "Could not find appropriate font face for character N for font
  # :/ubuntu_condensed.ttf", plus ":/help/button_a.svg missing".  Copying the same
  # 14 MB tree to /usr/local/bin/resources on that board and rerunning left a 5-line
  # log with zero font and zero help-icon errors, so this is the fix, not a guess.
  # Nothing else in the tree provides it: the theme package is not shipped in v21.
  [ -d "${PKG_BUILD}/resources" ] ||
    die "emulationstation: no resources/ in the source tree - ES would start with no fonts"
  cp -a "${PKG_BUILD}/resources" ${INSTALL}/usr/local/bin/resources
}
