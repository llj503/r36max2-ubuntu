# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2009-2016 Stephan Raue (stephan@openelec.tv)
# MPC for the self-built cross toolchain (host side only).

PKG_NAME="mpc"
PKG_VERSION="1.3.1"
PKG_SHA256="ab642492f5cf882b74aa0cb730cd410a81edcdbec895183ce930e706c1c759b8"
PKG_LICENSE="LGPL"
PKG_SITE="http://www.multiprecision.org/"
PKG_URL="https://ftp.gnu.org/gnu/mpc/${PKG_NAME}-${PKG_VERSION}.tar.gz"
PKG_DEPENDS_HOST="gmp:host mpfr:host"
PKG_LONGDESC="C library for arbitrary precision complex number arithmetic."

PKG_CONFIGURE_OPTS_HOST="--disable-static --enable-shared --with-gmp=${TOOLCHAIN} --with-mpfr=${TOOLCHAIN}"
