# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2009-2016 Stephan Raue (stephan@openelec.tv)
# Cross binutils for the self-built toolchain. Version pinned with the same
# sha256 ROCKNIX uses; built once into $TOOLCHAIN, never installed on the target.

PKG_NAME="binutils"
PKG_VERSION="2.44"
PKG_SHA256="67be9198476cc37436e2801de649f4ad80bf0d02430d86aff63c6b59b6e23987"
PKG_LICENSE="GPL"
PKG_SITE="https://ftp.gnu.org/gnu/binutils/"
PKG_URL="https://ftp.gnu.org/gnu/binutils/${PKG_NAME}-with-gold-${PKG_VERSION}.tar.xz"
PKG_DEPENDS_HOST="gmp:host"
PKG_LONGDESC="GNU binutils cross assembler/linker for ${TARGET_NAME}."

PKG_CONFIGURE_OPTS_HOST="--target=${TARGET_NAME} \
                         --with-sysroot=${SYSROOT_PREFIX} \
                         --with-gmp=${TOOLCHAIN} \
                         --with-gnu-as \
                         --with-gnu-ld \
                         --enable-ld=default \
                         --enable-plugins \
                         --disable-gold \
                         --disable-multilib \
                         --disable-nls \
                         --disable-werror \
                         --disable-gprofng \
                         --enable-checking=release \
                         --enable-shared \
                         --disable-gdb \
                         --disable-sim \
                         --disable-libdecnumber \
                         --disable-readline \
                         --with-system-zlib"

post_makeinstall_host() {
  # cross-recanonicalize: the sysroot is shared with gcc (built next); nothing
  # else to do here, but keep a marker documenting the toolchain layout
  mkdir -p ${TOOLCHAIN}/etc
  echo "binutils=${PKG_VERSION}" > ${TOOLCHAIN}/etc/r36max2-toolchain.binutils
}
