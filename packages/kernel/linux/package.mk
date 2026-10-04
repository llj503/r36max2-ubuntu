# SPDX-License-Identifier: GPL-2.0-or-later
# The single kernel for the R36 Max 2 image: latest mainline of the 7.2 series.
#
# v21 policy (user decision): no dual-kernel fallback any more - one modern
# kernel, plain artifact names on the FAT partition (Image, rk3326-xifan-*.dtb).
# 6.12.79 remains recoverable from git history and the v20 images.
#
# Not marked PKG_IS_KERNEL_PKG: that machinery injects a dependency on a
# package literally named "linux" pointing at this package itself; dependencies
# and the kernel-version stamp are written out by hand instead.

PKG_NAME="linux"
PKG_VERSION="7.2.9"
PKG_SHA256="b4c5dfbe51a364a6c7f03869200f88c8e1f77403539005f14b7fc6bc91b8d8ba"
PKG_LICENSE="GPL"
PKG_SITE="http://www.kernel.org"
PKG_URL="https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-${PKG_VERSION}.tar.xz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Mainline kernel ${PKG_VERSION} for the R36 Max 2."

# board patch dir + dtb list change -> rebuild the kernel
PKG_STAMP="${KERNEL_TARGET} ${R36_DTBS}"

PKG_PATCH_DIRS="board"

post_patch() {
  # carry the rocknix generic-dsi panel driver (vendored in sources/, adapted
  # to the 7.x DRM API by patches/board/0001) into the build
  if [ ! -e ${PKG_BUILD}/drivers/gpu/drm/panel/panel-generic-dsi.c ]; then
    die "linux: panel-generic-dsi.c missing after unpack - sources overlay broken?"
  fi
  grep -q panel-generic-dsi ${PKG_BUILD}/drivers/gpu/drm/panel/Makefile || \
    echo 'obj-$(CONFIG_DRM_PANEL_GENERIC_DSI) += panel-generic-dsi.o' >> ${PKG_BUILD}/drivers/gpu/drm/panel/Makefile

  # install the board device trees (repo is the single source of truth) and
  # wire them into the rockchip Makefile
  for f in ${PROJECT_DIR}/${PROJECT}/dt/*.dts ${PROJECT_DIR}/${PROJECT}/dt/*.dtsi; do
    [ -e "${f}" ] || continue
    cp -f "${f}" ${PKG_BUILD}/arch/arm64/boot/dts/rockchip/
  done
  for dtb in ${R36_DTBS}; do
    if ! grep -q "${dtb}.dtb" ${PKG_BUILD}/arch/arm64/boot/dts/rockchip/Makefile; then
      echo "dtb-\$(CONFIG_ARCH_ROCKCHIP) += ${dtb}.dtb" >> ${PKG_BUILD}/arch/arm64/boot/dts/rockchip/Makefile
    fi
  done
}

make_host() {
  :
}

makeinstall_host() {
  # headers into the sysroot for anything that compiles against the kernel
  make \
    ARCH=${TARGET_KERNEL_ARCH} \
    HOSTCC="${TOOLCHAIN}/bin/host-gcc" \
    HOSTCXX="${TOOLCHAIN}/bin/host-g++" \
    INSTALL_HDR_PATH=dest \
    headers_install
  mkdir -p ${SYSROOT_PREFIX}/usr/include
    cp -R dest/include/* ${SYSROOT_PREFIX}/usr/include
}

pre_make_target() {
  cp ${PROJECT_DIR}/${PROJECT}/linux/linux.aarch64.conf ${PKG_BUILD}/.config

  # deterministic build identity (see config/options)
  ${PKG_BUILD}/scripts/config --set-str CONFIG_DEFAULT_HOSTNAME "${DISTRONAME}"
  # the config is a rocknix template: their build system substitutes
  # @INITRAMFS_SOURCE@; we boot via the external uInitrd instead
  ${PKG_BUILD}/scripts/config --set-str CONFIG_INITRAMFS_SOURCE ""

  kernel_make listnewconfig
  # accept default answers for .config changes (same policy as v20's olddefconfig)
  yes "" | kernel_make oldconfig >/dev/null
}

make_target() {
  kernel_make Image modules
  for dtb in ${R36_DTBS}; do
    kernel_make rockchip/${dtb}.dtb
  done
}

makeinstall_target() {
  # modules in plain Ubuntu layout under the package install dir; mkimage
  # copies <install>/lib/modules into the rootfs
  kernel_make INSTALL_MOD_PATH=${INSTALL} modules_install
  rm -f ${INSTALL}/lib/modules/*/build ${INSTALL}/lib/modules/*/source

  # boot artifacts under the plain names the FAT partition and boot.ini use
  mkdir -p ${INSTALL}/.image
    cp -P ${PKG_BUILD}/arch/arm64/boot/Image ${INSTALL}/.image/Image
  for dtb in ${R36_DTBS}; do
    cp -P ${PKG_BUILD}/arch/arm64/boot/dts/rockchip/${dtb}.dtb ${INSTALL}/.image/${dtb}.dtb
  done
}
