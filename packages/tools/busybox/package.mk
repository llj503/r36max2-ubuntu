# SPDX-License-Identifier: GPL-2.0-or-later
# busybox: static arm64 busybox for the initramfs. Replaces the v20 pipeline's
# unpinned prebuilt binary (which lived only on the build host, never in git).

PKG_NAME="busybox"
PKG_VERSION="1.38.0"
PKG_SHA256="34f9ea6ff8636f2c9241153b9114eefa9e65674a45318ae1ef95bb5f31c53bb2"
PKG_LICENSE="GPL"
PKG_SITE="https://busybox.net/"
PKG_URL="https://busybox.net/downloads/busybox-${PKG_VERSION}.tar.bz2"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Static busybox for the r36max2 initramfs."

pre_configure_target() {
  make defconfig
  # static: the initramfs has no libc
  sed -i 's|^# CONFIG_STATIC is not set|CONFIG_STATIC=y|' .config
  # tc needs TCA_CBQ_* which modern kernel uapi headers removed
  sed -i 's|^CONFIG_TC=y|# CONFIG_TC is not set|' .config
}

# the framework exports CFLAGS/CPPFLAGS/CC pointing at the target; busybox's
# Kbuild feeds those into its HOST-side applet compile (plain gcc chokes on
# -march=armv8-a/-mabi=lp64). Build in a scrubbed env and pass target flags
# explicitly: CROSS_COMPILE for target objects, CFLAGS_EXTRA into kbuild.
make_target() {
  env -u CC -u CXX -u CPP -u LD -u AR -u NM -u STRIP \
      -u CFLAGS -u CPPFLAGS -u CXXFLAGS -u LDFLAGS \
    make CROSS_COMPILE="${TARGET_PREFIX}" \
      CFLAGS_EXTRA="${TARGET_CFLAGS}" \
      LDFLAGS_EXTRA="${TARGET_LDFLAGS}"
}

makeinstall_target() {
  mkdir -p ${INSTALL}/.initrd/bin
    cp busybox ${INSTALL}/.initrd/bin/busybox
}
