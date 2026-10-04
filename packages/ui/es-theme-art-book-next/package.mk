# SPDX-License-Identifier: GPL-2.0-or-later
# es-theme-art-book-next: the ES theme, pinned with the same rev + sha256 the
# v20 workflow verified (theme-stage-local.sh, itself cross-checked against
# ROCKNIX's package.mk pin).

PKG_NAME="es-theme-art-book-next"
PKG_VERSION="9a50ef366e750aabfab29e6915a2867607212971"
PKG_SHA256="7ee1e93f2c4e4f7385b78680ecfa3828acf12bc616e2111d23cc66a524231125"
PKG_LICENSE="Theme: CC-BY-NC-SA (see upstream)"
PKG_SITE="https://github.com/anthonycaccese/art-book-next-es"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="rootfs-apt"
PKG_LONGDESC="art-book-next ES theme (Batocera variant) for the R36 Max 2."
PKG_TOOLCHAIN="manual"

make_target() {
  :
}

makeinstall_target() {
  # install with hard links when possible (288 MB theme, same filesystem) and
  # DO NOT prune artwork variants - this theme references
  # ./_inc/systems/artwork-noir/_default.png directly, not via <include>
  # (see EMULATIONSTATION.md; tools/theme/verify/theme-check-local.py)
  local DEST="${INSTALL}/root/.emulationstation/themes/art-book-next"
  mkdir -p "${DEST}"
  cp -al ${PKG_BUILD}/. "${DEST}/" 2>/dev/null || cp -a ${PKG_BUILD}/. "${DEST}/"
}
