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
  # the archive tarball has no submodules; pugixml is pinned in .gitmodules
  local PUGI_REV="$(sed -n 's/.*pugixml.*revision = \([0-9a-f]*\).*/\1/p' ${PKG_BUILD}/.gitmodules | head -1)"
  [ -n "${PUGI_REV}" ] || die "emulationstation: cannot read pugixml pin from .gitmodules"
  curl -fsSL --retry 3 -o ${PKG_BUILD}/pugixml.tar.gz \
    "https://github.com/zeux/pugixml/archive/${PUGI_REV}.tar.gz" ||
    die "emulationstation: pugixml download failed"
  mkdir -p ${PKG_BUILD}/external/pugixml
  tar -xzf ${PKG_BUILD}/pugixml.tar.gz -C ${PKG_BUILD}/external/pugixml --strip-components=1
}

makeinstall_target() {
  # binary is at the repo root (upstream overrides CMAKE_RUNTIME_OUTPUT_DIRECTORY)
  local BIN="${PKG_BUILD}/emulationstation"
  [ -f "${BIN}" ] || BIN="${PKG_BUILD}/es-app/emulationstation"
  [ -f "${BIN}" ] || die "emulationstation: binary not found after build"
  mkdir -p ${INSTALL}/usr/local/bin
    cp "${BIN}" ${INSTALL}/usr/local/bin/emulationstation
}
