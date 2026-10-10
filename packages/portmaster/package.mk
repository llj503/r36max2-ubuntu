# SPDX-License-Identifier: GPL-2.0-or-later
# PortMaster runtime: the tool that installs community game ports.
#
# What ships in the image is the official release archive, pinned, and nothing else:
# the ports themselves are installed on the device by PortMaster over the network
# (decision 2026-10-10).  That keeps the image reproducible - a port is a download,
# not a build product - and the runtime is 24 MB.
#
# Reference for the shape of this recipe: ROCKNIX does the same thing
# (projects/ROCKNIX/packages/apps/portmaster/package.mk: pinned PortMaster.zip,
# unzipped on first use, STRIP disabled).  Their release pin was one behind this one
# when checked (2026.09.13-0343 vs 2026.10.03-1041).

PKG_NAME="portmaster"
PKG_VERSION="2026.10.03-1041"
# Computed here from the downloaded asset, then cross-checked against the md5 the
# release publishes for the same file (md5 742c4f335bd44ec03b7872510b098912), so a
# swapped asset would have to break both.
PKG_SHA256="6e4fa938c39efdb9237aa9973b3ce3f318242ada171f26cd72511b09e393fdf2"
PKG_LICENSE="MIT"
PKG_SITE="https://github.com/PortsMaster/PortMaster-GUI"
PKG_URL="${PKG_SITE}/releases/download/${PKG_VERSION}/PortMaster.zip"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="PortMaster: installs and runs community game ports; the runtime ships pinned, ports are downloaded on the device."
PKG_TOOLCHAIN="manual"

makeinstall_target() {
  # The archive contains prebuilt aarch64 binaries (gptokeyb, gptokeyb2, xdelta3,
  # astcenc).  Turning ${STRIP} into `true` makes the framework's install cleanup a
  # no-op for them, which is what upstream ships and what keeps them byte-identical
  # to the verified archive.  This matters here specifically: on this image the
  # stripped EmulationStation binary is what cost a core-dump analysis its symbols.
  export STRIP=true

  local CACHED="${SOURCES}/${PKG_NAME}/PortMaster-${PKG_VERSION}.zip"
  if [ ! -f "${CACHED}" ]; then
    mkdir -p "${SOURCES}/${PKG_NAME}"
    curl -fsSL --retry 3 -o "${CACHED}" "${PKG_URL}" ||
      die "portmaster: cannot fetch ${PKG_URL}"
  fi
  echo "${PKG_SHA256}  ${CACHED}" | sha256sum -c --status ||
    die "portmaster: PortMaster.zip does not match its pinned sha256"

  # Staging area only; /roms/ports is written on first use by r36-portmaster, so the
  # image carries one zip rather than an extracted tree that a PortMaster update
  # would then have to reconcile.
  mkdir -p ${INSTALL}/usr/config/PortMaster/release
  cp -f "${CACHED}" ${INSTALL}/usr/config/PortMaster/release/PortMaster.zip

  mkdir -p ${INSTALL}/usr/local/bin
  cp ${PKG_DIR}/scripts/r36-portmaster ${INSTALL}/usr/local/bin/r36-portmaster
  cp ${PKG_DIR}/scripts/r36-port     ${INSTALL}/usr/local/bin/r36-port
  chmod 755 ${INSTALL}/usr/local/bin/r36-portmaster ${INSTALL}/usr/local/bin/r36-port

  # The ES entry point: es_systems.cfg lists .sh files directly under /roms/ports,
  # so this is what makes "Start PortMaster" appear in the Ports system.
  mkdir -p ${INSTALL}/roms/ports
  cp "${PKG_DIR}/ports/Start PortMaster.sh" "${INSTALL}/roms/ports/Start PortMaster.sh"
  chmod 755 "${INSTALL}/roms/ports/Start PortMaster.sh"
}
