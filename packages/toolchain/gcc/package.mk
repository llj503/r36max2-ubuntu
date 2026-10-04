# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2009-2016 Stephan Raue (stephan@openelec.tv)
# Cross gcc for the self-built toolchain - SINGLE pass.
#
# The rocknix framework needs the classic two-stage bootstrap (minimal cc ->
# glibc -> full gcc) because it builds its own target libc. We do not: the
# target libc is the Ubuntu rootfs, provided by the rootfs-base package,
# whose makeinstall_target mirrors /usr/include and /usr/lib into
# ${SYSROOT_PREFIX} (with triplet-compat symlinks) BEFORE this package builds.
# So one full gcc pass against that sysroot is enough for kernel, modules and
# every target userspace program we ship.

PKG_NAME="gcc"
PKG_VERSION="15.1.0"
PKG_SHA256="e2b09ec21660f01fecffb715e0120265216943f038d0e48a9868713e54f06cea"
PKG_LICENSE="GPL-2.0-or-later"
PKG_SITE="https://gcc.gnu.org/"
PKG_URL="https://ftp.gnu.org/gnu/gcc/${PKG_NAME}-${PKG_VERSION}/${PKG_NAME}-${PKG_VERSION}.tar.xz"
PKG_DEPENDS_HOST="binutils:host gmp:host mpfr:host mpc:host rootfs-base"
PKG_LONGDESC="GNU Compiler Collection, cross-built for ${TARGET_NAME}."

GCC_COMMON_CONFIGURE_OPTS="--target=${TARGET_NAME} \
                           --with-sysroot=${SYSROOT_PREFIX} \
                           --with-gmp=${TOOLCHAIN} \
                           --with-mpfr=${TOOLCHAIN} \
                           --with-mpc=${TOOLCHAIN} \
                           --with-gnu-as \
                           --with-gnu-ld \
                           --enable-ld=default \
                           --with-linker-hash-style=gnu \
                           --disable-multilib \
                           --disable-nls \
                           --enable-checking=release \
                           --without-ppl \
                           --without-cloog \
                           --disable-lto \
                           --disable-libada \
                           --disable-libmudflap \
                           --disable-libitm \
                           --disable-libquadmath \
                           --disable-libgomp \
                           --disable-libsanitizer \
                           --disable-libssp \
                           --disable-libatomic \
                           --enable-__cxa_atexit"

PKG_CONFIGURE_OPTS_HOST="${GCC_COMMON_CONFIGURE_OPTS} \
                         --enable-languages=c,c++ \
                         --enable-tls \
                         --enable-shared \
                         --disable-static \
                         --enable-long-long \
                         --enable-threads=posix \
                         --disable-libstdcxx-pch \
                         --enable-libstdcxx-time \
                         --enable-clocale=gnu \
                         ${TARGET_ARCH_GCC_OPTS}"

pre_configure_host() {
  unset CPP
}

post_make_host() {
  # fix wrong link
  rm -rf ${TARGET_NAME}/libgcc/libgcc_s.so
  ln -sf libgcc_s.so.1 ${TARGET_NAME}/libgcc/libgcc_s.so
}

post_makeinstall_host() {
  # The host compiler wrappers are plain aliases (no ccache in this framework).
  # config/path creates them before this package builds; nothing to wrap here.

  # document toolchain versions for the build manifest
  mkdir -p ${TOOLCHAIN}/etc
  echo "gcc=${PKG_VERSION}" > ${TOOLCHAIN}/etc/r36max2-toolchain.gcc
  ${TARGET_PREFIX}gcc -dumpversion > ${TOOLCHAIN}/etc/r36max2-toolchain.gcc-version

  # keep the toolchain's own libs resolvable for later host builds
  echo "${TOOLCHAIN}/lib" > ${TOOLCHAIN}/etc/ld.so.conf 2>/dev/null || true
}

configure_target() {
  : # target pass intentionally unused - userspace links against the Ubuntu rootfs
}

make_target() {
  :
}
