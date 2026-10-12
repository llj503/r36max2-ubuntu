# SPDX-License-Identifier: GPL-2.0-or-later
# es-launcher: configs and launcher for the batocera-branch
# EmulationStation cross-compiled by the emulationstation package (M5). The
# input configs are the hardware-verified 17-key/4-axis mappings.

PKG_NAME="es-launcher"
PKG_VERSION="1.0"
PKG_LICENSE="GPL-2.0-or-later"
PKG_SITE="https://github.com/llj503/r36max2-ubuntu"
PKG_URL=""
PKG_DEPENDS_TARGET="rootfs-apt"
PKG_LONGDESC="EmulationStation launcher + verified input configs for the R36 Max 2."
PKG_TOOLCHAIN="manual"

make_target() {
  :
}

makeinstall_target() {
  install -m 755 ${PKG_DIR}/r36-es ${INSTALL}/usr/local/bin/r36-es
  install -m 755 ${PKG_DIR}/r36-play ${INSTALL}/usr/local/bin/r36-play

  # Boot straight into ES. Without this the device comes up on the console status page
  # and ES has to be started by hand over SSH, which is not a thing a handheld can do.
  mkdir -p ${INSTALL}/usr/lib/systemd/system
  install -m 644 ${PKG_DIR}/r36-es.service ${INSTALL}/usr/lib/systemd/system/r36-es.service
  enable_service r36-es.service

  # The ROM tree has to exist before ES starts, or a system whose <path> is missing is
  # dropped from the list silently (the "demo" entry proved this: ES logged
  # 'System "demo" path does not exist !' and then showed nothing). Directory names
  # match the user's ROM pack so games can be copied in without renaming.
  #
  # Each one carries a .keep file. Empty directories written by makeinstall_target did
  # not survive into the image at all - the first build of this recipe created 27 of
  # them and the packed root had none, with no error anywhere - so nothing here trusts
  # an empty dir to make it through the staging merge, and scripts/image asserts the
  # tree instead of assuming it.
  mkdir -p ${INSTALL}/roms
  for s in nes snes gb gbc gba fds megadrive mastersystem gamegear pcengine pcfx \
           atari2600 atari7800 atarilynx coleco vectrex neogeo cps1 cps2 arcade \
           fbneo psx n64 saturn dreamcast psp nds gw chaiplus openbor; do
    mkdir -p ${INSTALL}/roms/${s}
    printf '%s\n' "Drop games for this system here. ES only lists a system once it holds at least one file with an extension its es_systems.cfg entry declares." \
      > ${INSTALL}/roms/${s}/.keep
  done
  mkdir -p ${INSTALL}/roms/bios
  printf '%s\n' "BIOS files for the systems that need them (psx, saturn, dreamcast, ...)." \
    > ${INSTALL}/roms/bios/.keep
  # Dreamcast is not a flat file in this board's layout: flycast asks the frontend for
  # the system directory and then looks for the BIOS inside a dc/ subdir, measured with
  # the core on hardware - without the subdir it logged "Unable to find bios in
  # /roms/bios/dc/" and stopped. It also writes dc_nvmem.bin and vmu_save_*.bin there,
  # so this is the directory the emulated flash lives in, not just a lookup path.
  mkdir -p ${INSTALL}/roms/bios/dc
  printf '%s\n' "Put dc_boot.bin here (flycast looks in <system_directory>/dc/, and writes dc_nvmem.bin and vmu_save_*.bin next to it)." \
    > ${INSTALL}/roms/bios/dc/.keep
  # FBNeo's extra content (Neo Geo's neogeo.zip BIOS above all, plus its samples and
  # hi-score files) is looked up as <system_directory>/fbneo/<name> and
  # <system_directory>/fbneo/{arcade,consoles}/<name>, measured in locate_archive,
  # libretro.cpp:925-1000. system_directory is /roms/bios (retroarch.cfg), so this is the
  # directory the core actually searches. Without neogeo.zip every Neo Geo game fails with
  # "Cannot find required rom: neogeo.zip".
  mkdir -p ${INSTALL}/roms/bios/fbneo
  printf '%s\n' "Put neogeo.zip here (FBNeo searches <system_directory>/fbneo/ for its BIOS and samples; the ROM pack carries this file in bios/)." \
    > ${INSTALL}/roms/bios/fbneo/.keep

  # RetroArch's board settings, passed with --appendconfig by r36-play. See the header
  # of the file for why shipping it is not optional.
  mkdir -p ${INSTALL}/etc/r36
  install -m 644 ${PKG_DIR}/retroarch.cfg ${INSTALL}/etc/r36/retroarch.cfg

  # ES reads two filenames and nothing else - es_input.cfg and es_systems.cfg - looked
  # up in ~/.emulationstation first, then /etc/emulationstation.  Installing the
  # hardware-verified map under its repo name (es-input-r36max2.cfg) left it unread, so
  # the device booted into the "press a key to configure your controller" screen with no
  # keyboard attached.  The root copy is what the working card has; the /etc one covers
  # the ubuntu account.
  #
  # es_systems.cfg is not optional: this fork logs "ERROR es_systems.cfg file does not
  # exist!" and exits, and with zero systems no theme is ever looked up, so a fresh
  # image would show nothing to look at either.  Both copies carry this board's SDL GUID
  # and the joystick1left/joystick1up axis bindings (menu navigation only consumes
  # *left/*up names or joystick1* axes; leftanalog* has no consumer in this fork).
  mkdir -p ${INSTALL}/etc/emulationstation ${INSTALL}/root/.emulationstation
  install -m 644 ${PKG_DIR}/es-input-r36max2.cfg ${INSTALL}/etc/emulationstation/es_input.cfg
  install -m 644 ${PKG_DIR}/es-input-matched.cfg ${INSTALL}/etc/emulationstation/es-input-matched.cfg
  install -m 644 ${PKG_DIR}/es_systems.cfg       ${INSTALL}/etc/emulationstation/es_systems.cfg
  cp -f ${INSTALL}/etc/emulationstation/es_input.cfg    ${INSTALL}/root/.emulationstation/es_input.cfg
  cp -f ${INSTALL}/etc/emulationstation/es_systems.cfg  ${INSTALL}/root/.emulationstation/es_systems.cfg
}
