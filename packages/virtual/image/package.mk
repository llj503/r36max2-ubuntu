# SPDX-License-Identifier: GPL-2.0-or-later
# Virtual package: the complete image payload. Building this assembles the
# entire dependency graph (toolchain -> kernel + modules -> rootfs layers ->
# device packages); scripts/image then packs ${BUILD}/image/system + the boot
# artifacts into the .img.

PKG_NAME="image"
PKG_LICENSE="GPL"
PKG_SITE="https://github.com/llj503/r36max2-ubuntu"
# es-theme-art-book-next (288 MB unpacked) is deliberately NOT in this list: decided
# 2026-10-04, v21 ships without it and the first boot is checked before it goes back in.
# It stays a pinned input in packages/ui/, so re-adding it is one line.
PKG_DEPENDS_TARGET="toolchain rootfs-base rootfs-apt \
  linux rocknix-joypad aic8800 aic8800-dc-fw \
  gpu-demos busybox initramfs \
  bootlog status-screen wifi-setup expand-root fwswap \
  usb-gadget audio keymapper osk wayland \
  emulationstation es-launcher \
  libretro-fceumm libretro-gambatte libretro-mgba libretro-snes9x2010 libretro-vba-next \
  libretro-pcsx-rearmed libretro-flycast libretro-mednafen-saturn"
PKG_SECTION="virtual"
PKG_LONGDESC="Root package: everything that goes into the r36max2 image."
