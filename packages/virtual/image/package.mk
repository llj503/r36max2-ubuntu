# SPDX-License-Identifier: GPL-2.0-or-later
# Virtual package: the complete image payload. Building this assembles the
# entire dependency graph (toolchain -> kernel + modules -> rootfs layers ->
# device packages); scripts/image then packs ${BUILD}/image/system + the boot
# artifacts into the .img.

PKG_NAME="image"
PKG_LICENSE="GPL"
PKG_SITE="https://github.com/llj503/r36max2-ubuntu"
PKG_DEPENDS_TARGET="toolchain rootfs-base rootfs-apt \
  linux rocknix-joypad aic8800 aic8800-dc-fw \
  gpu-demos busybox initramfs \
  bootlog status-screen wifi-setup expand-root fwswap \
  usb-gadget audio keymapper osk wayland \
  emulationstation es-theme-art-book-next es-launcher"
PKG_SECTION="virtual"
PKG_LONGDESC="Root package: everything that goes into the r36max2 image."
