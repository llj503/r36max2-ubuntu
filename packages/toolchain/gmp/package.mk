# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2009-2016 Stephan Raue (stephan@openelec.tv)
# GMP for the self-built cross toolchain (host side only).

PKG_NAME="gmp"
PKG_VERSION="6.3.0"
PKG_SHA256="a3c2b80201b89e68616f4ad30bc66aee4927c3ce50e33929ca819d5c43538898"
PKG_LICENSE="LGPLv3"
PKG_SITE="https://gmplib.org/"
PKG_URL="https://ftp.gnu.org/gnu/gmp/${PKG_NAME}-${PKG_VERSION}.tar.xz"
PKG_DEPENDS_HOST=""
PKG_LONGDESC="GNU Multiple Precision Arithmetic Library."

PKG_CONFIGURE_OPTS_HOST="--enable-cxx --disable-static --enable-shared"

# gmp 6.3.0's configure probes predate C23: gcc>=15 defaults to -std=gnu23 where
# "void g(){}" means (void) and the reliability-test program stops compiling
pre_configure_host() {
  export CFLAGS="${CFLAGS} -std=gnu11"
}
