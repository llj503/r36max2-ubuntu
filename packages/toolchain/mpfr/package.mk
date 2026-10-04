# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2009-2016 Stephan Raue (stephan@openelec.tv)
# MPFR for the self-built cross toolchain (host side only).

PKG_NAME="mpfr"
PKG_VERSION="4.2.2"
PKG_SHA256="b67ba0383ef7e8a8563734e2e889ef5ec3c3b898a01d00fa0a6869ad81c6ce01"
PKG_LICENSE="LGPL"
PKG_SITE="https://www.mpfr.org/"
PKG_URL="https://ftpmirror.gnu.org/mpfr/${PKG_NAME}-${PKG_VERSION}.tar.xz"
PKG_DEPENDS_HOST="gmp:host"
PKG_LONGDESC="C library for multiple-precision floating-point computations."

PKG_CONFIGURE_OPTS_HOST="--disable-static --enable-shared --with-gmp=${TOOLCHAIN}"
