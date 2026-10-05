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

# board patch dir + dtb list change -> rebuild the kernel.  The hash of the project
# .config is folded in deliberately: calculate_stamp() covers ${PKG_DIR} and the
# project's patches/packages/${PKG_NAME} directories, and
# ${PROJECT_DIR}/${PROJECT}/linux/linux.aarch64.conf is none of those - so editing the
# kernel config changed no hash at all and the tree kept booting a kernel built from
# the old .config.  That is why the RD_GZIP fix sat in git while the card went on
# resetting: the rebuilt image contained the same Image as before.
# The dt sources must be in here: without them a change under projects/<P>/dt/
# left the stamp unchanged, so the package was skipped and the image silently
# shipped the previous dtbs (the board then boots a device tree you edited and
# never see).
PKG_STAMP="${KERNEL_TARGET} ${R36_DTBS} $(find ${PROJECT_DIR}/${PROJECT}/linux ${PROJECT_DIR}/${PROJECT}/dt -name '*.conf' -o -name '*.dts' -o -name '*.dtsi' -print0 2>/dev/null | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)"

PKG_PATCH_DIRS="board"

post_unpack() {
  # The panel driver this board needs is not upstream: it is ROCKNIX's
  # drivers/gpu/drm/panel/panel-generic-dsi.c, vendored right here next to the recipe
  # (sha256 165ee9622f5c4df37bb8e6bf940aae3f63d44147d54e6f9ce409921092153b61, GPL-2.0).
  # Two traps, both hit today:
  #   * it must be copied in during UNPACK, not post_patch - the board patches run in
  #     between, and "can't find file to patch: .../panel-generic-dsi.c" was the result;
  #   * it must not live in a directory named sources/: .gitignore has a bare
  #     `sources/` rule for the download cache, which silently matched
  #     packages/kernel/linux/sources/ and left the file untracked, so the next clone
  #     had no such file at all.  Beside package.mk cannot be swallowed by that rule.
  cp -f "${PKG_DIR}/panel-generic-dsi.c" \
        "${PKG_BUILD}/drivers/gpu/drm/panel/panel-generic-dsi.c" ||
    die "linux: cannot copy the vendored panel-generic-dsi.c into ${PKG_BUILD}"
}

post_patch() {
  [ -e ${PKG_BUILD}/drivers/gpu/drm/panel/panel-generic-dsi.c ] ||
    die "linux: panel-generic-dsi.c missing after unpack - post_unpack broken?"
  # no Kconfig symbol, no build: linux.aarch64.conf sets
  # CONFIG_DRM_PANEL_GENERIC_DSI=y, and `make olddefconfig` silently DROPS a setting
  # with no matching symbol - the same way CONFIG_INPUT_POLLDEV disappeared from the
  # hand-built tree and left the joypad failing at modpost. A dropped panel symbol
  # would mean a black panel, which on this board is not debuggable over a console.
  grep -q DRM_PANEL_GENERIC_DSI ${PKG_BUILD}/drivers/gpu/drm/panel/Kconfig ||
    cat >> ${PKG_BUILD}/drivers/gpu/drm/panel/Kconfig <<'KCONFIG'

config DRM_PANEL_GENERIC_DSI
	tristate "Generic DSI panel with a textual panel_description"
	depends on OF && DRM_MIPI_DSI
	help
	  Carried over from ROCKNIX: matches a DSI panel by the init sequence
	  description string in the DT instead of a hard-coded panel list.
KCONFIG
  # "depends on MIPI_DSI" is not a typo fix: mainline has no MIPI_DSI symbol, the
  # DSI helper is gated by DRM_MIPI_DSI.  A dependency on a symbol that does not
  # exist makes this one INVISIBLE, so oldconfig silently discarded the
  # CONFIG_DRM_PANEL_GENERIC_DSI=y from linux.aarch64.conf, panel-generic-dsi.o was
  # never compiled, and Image still built fine - a black panel with no serial
  # console to find it.  make_target asserts the .o for exactly that reason.
  grep -q panel-generic-dsi ${PKG_BUILD}/drivers/gpu/drm/panel/Makefile || \
    echo 'obj-$(CONFIG_DRM_PANEL_GENERIC_DSI) += panel-generic-dsi.o' >> ${PKG_BUILD}/drivers/gpu/drm/panel/Makefile
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
  # The board device trees are copied in here, not in post_patch.  PKG_STAMP hashes
  # projects/<P>/dt precisely so a dts edit cannot be skipped - but that only
  # invalidates build/install, and post_patch belongs to the patch phase, which does
  # not re-run.  Measured after a dts-only change: the repo dts was 29195 bytes and
  # the kernel tree still held the 28123-byte copy from three hours earlier, so
  # make dtbs rebuilt nothing, install staged the old 63819-byte .dtb, and the only
  # reason it was caught is that scripts/image asserts dr_mode/always-on against the
  # dtb that is actually in the image.
  for f in ${PROJECT_DIR}/${PROJECT}/dt/*.dts ${PROJECT_DIR}/${PROJECT}/dt/*.dtsi; do
    [ -e "${f}" ] || continue
    cp -f "${f}" ${PKG_BUILD}/arch/arm64/boot/dts/rockchip/
  done
  for dtb in ${R36_DTBS}; do
    if ! grep -q "${dtb}.dtb" ${PKG_BUILD}/arch/arm64/boot/dts/rockchip/Makefile; then
      echo "dtb-\$(CONFIG_ARCH_ROCKCHIP) += ${dtb}.dtb" >> ${PKG_BUILD}/arch/arm64/boot/dts/rockchip/Makefile
    fi
  done

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

  # the panel driver is the one thing a failed build cannot be noticed about on
  # this board: no UART, no keyboard, and the symptom is a dark screen
  grep -qx 'CONFIG_DRM_PANEL_GENERIC_DSI=y' ${PKG_BUILD}/.config ||
    die "linux: .config has no CONFIG_DRM_PANEL_GENERIC_DSI=y - the symbol is invisible, check its depends"
  [ -e ${PKG_BUILD}/drivers/gpu/drm/panel/panel-generic-dsi.o ] ||
    die "linux: panel-generic-dsi.o was not built - the DSI panel would come up black"

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
