# SPDX-License-Identifier: GPL-2.0-or-later
# rootfs-base: the Ubuntu 26.04 rootfs layer (root-free part).
#
# Unpacks the official ubuntu-base tarball (SHA256-pinned) and adds the
# -dev bootstrap set (libc6-dev, libstdc++-15-dev, linux-libc-dev, ...) by
# downloading version-exact .deb files from Ubuntu's snapshot service and
# unpacking them with dpkg-deb -x - no root needed, and the versions come from
# the pinned snapshot's Packages index so two builds resolve the same URLs.
#
# The remaining package set (runtime + dev chain + wayland stack) is installed
# by rootfs-apt via chroot, which needs sudo; device config and service
# enables live there too. This package mirrors the multiarch headers/libs into
# ${SYSROOT_PREFIX} so the self-built cross gcc (packages/toolchain/gcc) links
# against exactly the libc this image ships.

PKG_NAME="rootfs-base"
PKG_VERSION="26.04.1"
PKG_SHA256="5a1906794ced63a71a8119c3f211ef5f0bbe0a243001b4bbd41fdf80c5b219fd"
PKG_LICENSE="mixed (Ubuntu base image)"
PKG_SITE="https://cdimage.ubuntu.com/ubuntu-base/"
PKG_URL="https://cdimage.ubuntu.com/ubuntu-base/releases/26.04/release/ubuntu-base-${PKG_VERSION}-base-arm64.tar.gz"
PKG_DEPENDS_TARGET=""
PKG_LONGDESC="Official minimal Ubuntu 26.04 arm64 base + pinned -dev bootstrap set (sysroot donor)."
PKG_TOOLCHAIN="manual"

# the -dev packages whose files the cross toolchain needs from the sysroot.
# Versions are NOT hardcoded: they resolve from the pinned snapshot index.
R36_SYSROOT_DEBS="libc6-dev libstdc++-15-dev gcc-15-base linux-libc-dev libgcc-s1 libstdc++6 libc6"

# the tarball has no top-level directory: entries are already flat (bin, usr/...)
unpack() {
  mkdir -p "${PKG_BUILD}"
  tar -xzf "${SOURCES}/${PKG_NAME}/${PKG_SOURCE_NAME}" -C "${PKG_BUILD}"
}

make_target() {
  :
}

# resolve the exact .deb filename for one package from the pinned snapshot's
# Packages index. stdout: path relative to the snapshot root.
_r36_resolve_deb() {  # $1=package name
  local pkg="$1" idx="${R36_PKGIDX}"
  awk -v pkg="${pkg}" '
    $1 == "Package:" { name=$2 }
    $1 == "Filename:" && name == pkg { print $2; exit }
  ' "${idx}"
}

_r36_fetch_deb() {  # $1=package name, $2=dest dir
  local pkg="$1" dest="$2" fn rel url
  rel="$(_r36_resolve_deb "${pkg}")"
  [ -n "${rel}" ] || die "rootfs-base: ${pkg} not found in the pinned snapshot index"
  fn="${rel##*/}"
  url="https://${APT_MIRROR_HOST}/ubuntu/${APT_SNAPSHOT}/${rel}"
  if [ ! -f "${dest}/${fn}" ]; then
    build_msg "CLR_GET" "GET" "deb ${pkg} (${fn})" "indent"
    curl -fsSL --retry 3 -o "${dest}/${fn}" "${url}" ||
      die "rootfs-base: download failed: ${url}"
  fi
  echo "${dest}/${fn}"
}

makeinstall_target() {
  # --- 1. the base tree becomes the image staging tree -----------------------
  # (written directly into ${BUILD}/image/system: the tar-merge in scripts/install
  # would drop the dev headers this image intentionally ships)
  local R="${BUILD}/image/system"
  # wipe, don't merge: a stale tree from an earlier run makes rsync trip over
  # the merged-usr symlinks (bin/lib/sbin) ("cannot delete non-empty directory")
  rm -rf "${R}"
  mkdir -p "${R}"
  rsync -a "${PKG_BUILD}/" "${R}/"

  # --- 2. -dev bootstrap set from the pinned snapshot (no root needed) -------
  local IDX_URL="https://${APT_MIRROR_HOST}/ubuntu/${APT_SNAPSHOT}/dists/resolute/main/binary-arm64/Packages.gz"
  export R36_PKGIDX="${BUILD}/.${PKG_NAME}-Packages-index"
  if [ ! -s "${R36_PKGIDX}" ]; then
    curl -fsSL --retry 3 -o "${R36_PKGIDX}.gz" "${IDX_URL}" ||
      die "rootfs-base: cannot fetch snapshot Packages index"
    zcat "${R36_PKGIDX}.gz" > "${R36_PKGIDX}"
  fi
  local DEBDIR="${BUILD}/.${PKG_NAME}-debs"
  mkdir -p "${DEBDIR}"
  local deb
  for p in ${R36_SYSROOT_DEBS}; do
    deb="$(_r36_fetch_deb "${p}" "${DEBDIR}")"
    dpkg-deb -x "${deb}" "${R}"
  done

  # --- 3. mirror the multiarch sysroot for the self-built cross gcc ----------
  # gcc is configured --with-sysroot=${SYSROOT_PREFIX} with our own triplet
  # (aarch64-r36max2-linux-gnu); Ubuntu uses aarch64-linux-gnu multiarch dirs,
  # so mirror the dev content and add triplet-compat symlinks.
  local SR="${SYSROOT_PREFIX}"
  mkdir -p "${SR}/usr" "${SR}/lib"
  rm -rf "${SR}/usr/include" "${SR}/usr/lib/aarch64-linux-gnu" "${SR}/lib/aarch64-linux-gnu"
  cp -a "${R}/usr/include" "${SR}/usr/include"
  [ -d "${R}/usr/lib/aarch64-linux-gnu" ] && \
    cp -a "${R}/usr/lib/aarch64-linux-gnu" "${SR}/usr/lib/aarch64-linux-gnu"
  [ -d "${R}/lib/aarch64-linux-gnu" ] && \
    cp -a "${R}/lib/aarch64-linux-gnu" "${SR}/lib/aarch64-linux-gnu"
  ln -sfn aarch64-linux-gnu "${SR}/usr/include/aarch64-r36max2-linux-gnu"
  ln -sfn aarch64-linux-gnu "${SR}/usr/lib/aarch64-r36max2-linux-gnu"
  ln -sfn aarch64-linux-gnu "${SR}/lib/aarch64-r36max2-linux-gnu"
  # gcc's aarch64 default dynamic-linker path is the vanilla
  # /lib/ld-linux-aarch64.so.1; Ubuntu keeps the loader in the multiarch dir
  ln -sfn aarch64-linux-gnu/ld-linux-aarch64.so.1 "${SR}/lib/ld-linux-aarch64.so.1"
}
