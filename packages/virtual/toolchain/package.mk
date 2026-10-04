# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2018-present Team LibreELEC (https://libreelec.tv)
# Virtual package: the self-built cross toolchain. Every target package
# depends on this, which is what makes "toolchain first" hold.

PKG_NAME="toolchain"
PKG_VERSION="1.0"
PKG_LICENSE="GPL"
PKG_SECTION="virtual"
PKG_LONGDESC="Virtual package for the self-built cross toolchain."

PKG_DEPENDS_HOST="gmp:host mpfr:host mpc:host binutils:host"
PKG_DEPENDS_TARGET="gcc:host binutils:host"
