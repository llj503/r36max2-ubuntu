# SPDX-License-Identifier: GPL-2.0-or-later
# Virtual package: the complete image payload. Building this assembles the
# entire dependency graph (toolchain -> kernel + modules -> rootfs layers ->
# device packages); scripts/image then packs ${BUILD}/image/system + the boot
# artifacts into the .img.

PKG_NAME="image"
PKG_LICENSE="GPL"
PKG_SITE="https://github.com/llj503/r36max2-ubuntu"
# es-theme-art-book-next went back in on 2026-10-09: it had been excluded on 2026-10-04
# only so a first boot could be checked without it, and that check has passed (see
# distributions/ and EMULATIONSTATION.md). It is 288 MB unpacked, installed with hard links.
PKG_DEPENDS_TARGET="toolchain rootfs-base rootfs-apt \
  linux rocknix-joypad aic8800 aic8800-dc-fw \
  gpu-demos busybox initramfs \
  bootlog status-screen wifi-setup expand-root fwswap \
  usb-gadget audio keymapper osk wayland \
  emulationstation es-launcher es-theme-art-book-next portmaster \
  libretro-fceumm libretro-gambatte libretro-mgba libretro-snes9x2010 libretro-vba-next \
  libretro-pcsx-rearmed libretro-flycast libretro-mednafen-saturn libretro-parallel-n64 \
  libretro-fbneoplus libretro-gpsp-ezode"
PKG_SECTION="virtual"
PKG_LONGDESC="Root package: everything that goes into the r36max2 image."
