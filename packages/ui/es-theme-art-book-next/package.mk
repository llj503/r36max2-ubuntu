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

  # Installing the theme is only half of it: ES picks the theme from the ThemeSet
  # *setting*, whose default is "system-theme", so without this file a card with the
  # theme present still shows the built-in one. Format is from this fork's own writer
  # (es-core/src/Settings.cpp:508, a <config> root with <string name= value=/> children)
  # - the card had no es_settings.cfg at all, because saveFile() only runs when a setting
  # is actually changed, so nothing here could be copied from a working device.
  # ES rewrites this file on the first user change and keeps ThemeSet, so shipping a
  # one-line file is not a freeze of the rest of the settings.
  #
  # Language is the key SystemConf::get("system.language") maps to when there is no
  # batocera.conf (es-core/src/SystemConf.cpp:18-19), i.e. exactly what picking
  # 简体中文 in the menu writes.  It is defaulted here because ES never applies it
  # itself: main.cpp:345-348 initialises gettext with an empty locale, so the UI
  # language is the environment.  r36-es reads this value and exports it.
  #
  # HideWindow is pinned because the whole product depends on it and the value it
  # would otherwise inherit is a preprocessor branch, not a config: FileData.cpp:718
  # reads it as `window->deinit(hideWindow)`, and only deinitRenderer=true reaches
  # Renderer::deinit() -> destroyWindow() -> SDL_Quit() (Renderer.cpp:504-508, 318-336),
  # which is the moment ES gives up DRM master. Measured on the board both ways: with
  # master held by ES, fceumm and fbneoplus both die in `video_driver_init_internal()`
  # and OpenBOR prints "SDL Failed to Init!!!! (kmsdrm not available)"; after an
  # SDL_Quit() of the same kind, /sys/kernel/debug/dri/0/state names the game as the
  # scanned-out framebuffer (retroarch / OpenBOR-ff / onsyuri) and each of them runs.
  # Settings.cpp:362-366 already defaults it to true when neither _WIN32/X86/X86_64 is
  # defined - this build defines none - so the pin does not change today's behaviour.
  # It changes what a future ES rebuild or the menu switch in GuiMenu.cpp:1143 costs:
  # false means every game on the card fails to start, silently, from the front end.
  #
  # The element has to be <bool>, not <string>: loadFile dispatches on the child name
  # (Settings.cpp:526-533 reads "bool"/"int"/"float"/"string" separately), so a <string>
  # with the same name is parsed into mStringMap and the bool keeps its default - the file
  # would look right and do nothing. saveFile (Settings.cpp:473) writes it back as "bool",
  # and only when it differs from mDefaultBoolMap, which is why the card's own copy has no
  # HideWindow line at all: it equals the compiled default.
  mkdir -p ${INSTALL}/root/.emulationstation
  cat > ${INSTALL}/root/.emulationstation/es_settings.cfg <<'EOS'
<!-- r36max2 default: select the installed art-book-next theme and the Simplified
     Chinese UI. Everything else is whatever this fork's Settings.cpp defaults are
     until the user changes it. -->
<config>
	<string name="ThemeSet" value="art-book-next" />
	<string name="Language" value="zh_CN" />
	<bool name="HideWindow" value="true" />
</config>
EOS
  # ES also reads a system-wide copy for other accounts; the root one is what the device
  # actually uses (r36-es runs as root with HOME=/root).
  mkdir -p ${INSTALL}/etc/emulationstation
  cp -f ${INSTALL}/root/.emulationstation/es_settings.cfg ${INSTALL}/etc/emulationstation/es_settings.cfg
}
