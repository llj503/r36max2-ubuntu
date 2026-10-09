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
# the theme is a runtime asset, not a build input; it is shipped by its own recipe
# (packages/ui/es-theme-art-book-next) and pulled in by packages/virtual/image
PKG_DEPENDS_TARGET="toolchain rootfs-apt"
PKG_LONGDESC="EmulationStation front end (emulationstation-next, GLES3), cross-built."
PKG_TOOLCHAIN="cmake-make"
# scripts/build strips ${INSTALL}/usr/share/locale from every target package as a
# size optimisation, but that is exactly where makeinstall_target below puts the
# gettext catalogs ES binds its "emulationstation2" domain to (main.cpp:348).  The
# deletion is silent - no error, the UI just stays English - which is how the first
# build of this recipe produced an image whose LANGUAGE menu did nothing.
PKG_BUILD_FLAGS="locale"

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

# locales to generate into /usr/lib/locale, one per UI language the device is meant
# to be able to run in.  The menu offers 35 languages and every catalog ships, but
# a language only actually translates if its locale exists here too (see
# makeinstall_target); each is ~3.1 MB.  Codes are the values GuiMenu.cpp:1511-1546
# writes into the "Language" setting.
ES_LOCALES_TO_GENERATE="zh_CN"

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

post_patch() {
  # Battery level read 0% on this board while /sys/class/power_supply/rk817-battery
  # said capacity=100.  Platform.cpp picks the battery by NAME substring, and its
  # "/bat" test needs a leading slash, so only a legacy .../power_supply/battery
  # entry can ever match; mainline names this gauge "rk817-battery".  Nothing
  # matched, so batteryCapacityPath stayed empty and ret.level kept its default 0
  # (Platform.h:58) - while hasBattery still came out true, because "charger" does
  # match rk817-charger.  Hence an icon at 0%, not "no battery".
  #
  # patches/0101-*.patch fixes it by resolving the device through its own type=
  # attribute, which is what /usr/local/sbin/r36-status-screen already does on this
  # board for the same reason (KNOWN-ISSUES.md, the batt: ?% entry).
  #
  # scripts/unpack applies patches/*.patch itself and does NOT check patch's exit
  # status, and BUILD_CLEANUP_INSTALL then deletes the *.rej that a failed apply
  # would leave behind - so a patch that stopped applying after an upstream bump
  # would vanish with no signal.  Assert the content instead.
  grep -q 'r36max2: every probe above matches on the device NAME' \
    ${PKG_BUILD}/es-core/src/utils/Platform.cpp ||
    die "emulationstation: the battery patch did not apply - ES would show 0% with a charged battery"

  # 0102: saving the settings menu aborted ES (rc=134) on this board, which is why a
  # language change never reached the file.  The GPU-governor save func calls
  # getSelected() unconditionally; that list is empty here because ES enumerates the
  # governors through /etc/profile.d/099-freqfunctions, a ROCKNIX-only helper this
  # rootfs has never had.  Located from a backtrace captured on the device by
  # interposing __cxa_throw, not by reading:
  #   GuiSettings.cpp:101 (save pass) -> GuiMenu.cpp:2139 -> vector<string>::at(0)
  # (the CPU-governor list above it is safe only because GuiMenu.cpp:2101-2102
  # appends a fallback entry; selectFirstItem() cannot select from nothing.)
  grep -q 'r36max2: getAvailableGpuGovernors() enumerates through' \
    ${PKG_BUILD}/es-app/src/guis/GuiMenu.cpp ||
    die "emulationstation: the gpu-governor guard did not apply - saving the settings menu would abort ES"
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
  [ -d "${PKG_BUILD}/resources" ] ||
    die "emulationstation: no resources/ in the source tree - ES would start with no fonts"
  cp -a "${PKG_BUILD}/resources" ${INSTALL}/usr/local/bin/resources

  # --- translations -----------------------------------------------------------
  # This build has -DHAVE_INTL (CMakeLists.txt:558-560 found msgfmt/msgmerge/
  # xgettext + Intl in the sysroot), so _(x) is plain glibc gettext and the ONLY
  # thing that can translate the UI is a catalog on disk: main.cpp:348 binds the
  # "emulationstation2" domain to /usr/share/locale (./locale/lang wins, but the
  # service runs with cwd=/).  Upstream's install rule puts the catalogs in
  # share/locale/<lang>/LC_MESSAGES (locale/CMakeLists.txt:33) and this recipe
  # never runs `make install`, so without the copy below the card had exactly
  # zero emulationstation2.mo files: the LANGUAGE menu row saves zh_CN and the
  # UI stays English, which is what "cannot switch to Simplified Chinese" was.
  # The .mo are built by the i18n target into the SOURCE tree, not the cmake dir.
  local CAT_SRC="${PKG_BUILD}/locale/lang"
  local cats=0 mo lang
  for mo in "${CAT_SRC}"/*/LC_MESSAGES/emulationstation2.mo; do
    [ -f "${mo}" ] || continue
    lang=$(basename "$(dirname "$(dirname "${mo}")")")
    mkdir -p "${INSTALL}/usr/share/locale/${lang}/LC_MESSAGES"
    cp -f "${mo}" "${INSTALL}/usr/share/locale/${lang}/LC_MESSAGES/emulationstation2.mo"
    cats=$((cats + 1))
  done
  [ "${cats}" -gt 0 ] ||
    die "emulationstation: no compiled catalogs under ${CAT_SRC} - the host needs msgfmt, msgmerge and xgettext or HAVE_INTL is off and nothing can ever be translated"

  # A catalog alone is not enough.  glibc gettext ignores LANGUAGE while the
  # effective locale is in the C family, and this rootfs ships no generated
  # locales at all (`locale -a` on the card = C, C.utf8, POSIX; there is no
  # /usr/share/i18n data to make one).  Measured on the board 2026-10-09 with the
  # real zh_CN catalog in place, through the same glibc gettext ES calls:
  #   LANG=C.UTF-8 LANGUAGE=zh_CN            -> "SETTINGS"   (ignored)
  #   LANG=C.UTF-8 LC_MESSAGES=zh_CN.UTF-8   -> "设置"        (works)
  # So the locale has to exist; r36-es then points LC_MESSAGES at it.  Generated
  # with the HOST localedef from the host's i18n data: the result is plain data
  # and a 2.39-generated zh_CN.UTF-8 loads on the card's glibc 2.43 (measured:
  # `locale -a` lists it and gettext returns the translation).  Each language
  # costs ~3.1 MB, which is why this is a list and not "all 35".
  # localedef prints errors but still exits 0, so success is the output dir.
  for lang in ${ES_LOCALES_TO_GENERATE}; do
    mkdir -p "${INSTALL}/usr/lib/locale"
    localedef -i "${lang}" -f UTF-8 "${INSTALL}/usr/lib/locale/${lang}.UTF-8" ||
      die "emulationstation: localedef failed for ${lang}"
    [ -f "${INSTALL}/usr/lib/locale/${lang}.UTF-8/LC_MESSAGES/SYS_LC_MESSAGES" ] ||
      die "emulationstation: localedef produced no ${lang}.UTF-8 - is /usr/share/i18n present on the build host?"
  done
}
