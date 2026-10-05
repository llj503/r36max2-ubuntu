# SPDX-License-Identifier: GPL-2.0-or-later
# aic8800-dc-fw: firmware for the AIC8800DC USB WiFi (chip_sub_id == 2, the
# h_u02 build - see HARDWARE.md).
#
# Pinned to the SAME tag as the driver (packages/kernel/aic8800), because the two
# are not interchangeable.  With the previous 4.0-tag blobs against the 5.0 driver
# the chip associated (connect_ind status_code:0) but both EAPOL frames came back
# "usb_host_cfm status=9", so the 4-way handshake never finished and no address was
# ever leased.  Replacing only the blob contents in /lib/firmware/aic8800DC - same
# driver, same everything else - made the handshake complete and wlan0 hold
# 192.168.0.143 for the whole time the chip stayed on the bus.
#
# The comment that used to live here ("radxa removed the 8800DC .bin files after
# 4.x") was wrong: the 5.0 tree ships all 20 files under src/USB/driver_fw/fw/
# aic8800DC, 13 of them byte-different from the 4.0 set.

PKG_NAME="aic8800-dc-fw"
PKG_VERSION="5.0+git20260123.5f7be68d-9"
PKG_SHA256="416f587eab1f7ce083d44991245158f7a602b21aed778b39b195b74c14a6609e"
PKG_LICENSE="Proprietary (AICSemi)"
PKG_SITE="https://github.com/radxa-pkg/aic8800"
PKG_URL="${PKG_SITE}/archive/refs/tags/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET=""
PKG_LONGDESC="AIC8800DC firmware bundle (fmacfw_patch_8800dc_h_u02.bin set)."
PKG_TOOLCHAIN="manual"

make_target() {
  :
}

makeinstall_target() {
  local FWDIR="${INSTALL}/lib/firmware/aic8800DC"
  mkdir -p "${FWDIR}"
  cp -a ${PKG_BUILD}/src/USB/driver_fw/fw/aic8800DC/. "${FWDIR}/"
}
