#!/bin/bash
# require-arm64.sh - make sure this host can actually execute the arm64 binaries that
# live in a staging rootfs, before any script starts chrooting into it.
#
#   bash scripts/require-arm64.sh "${BUILD}/image/system"
#
# Why this exists as its own step: the binfmt rule is runtime state in /proc, so
# "my chroot worked an hour ago" is not something the pipeline may assume - an idle
# WSL VM restart drops it.  Without a handler every chroot fails with "Exec format
# error", and the scripts that ignored that kept writing config files and printed
# ROOTFS BUILD DONE over a rootfs with nothing installed in it (measured 2026-10-04).
set -u
REPO=${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
ROOT=${1:?usage: require-arm64.sh <rootfs-dir>}

ok() { chroot "$ROOT" /bin/sh -c 'uname -m' 2>/dev/null | grep -q aarch64; }

if ok; then
  echo "  arm64 chroot works in $ROOT"
  exit 0
fi

echo "  no working arm64 handler for $ROOT - registering the packaged rule"
bash "$REPO/scripts/register-binfmt-aarch64.sh" "$ROOT"
if ok; then
  echo "  arm64 chroot works now ($(chroot "$ROOT" /bin/sh -c 'uname -m'))"
  exit 0
fi

echo "!! still cannot execute arm64 in a chroot."
echo "   check:  ls /proc/sys/fs/binfmt_misc/           (want qemu-aarch64)"
echo "           apt-get install qemu-user-static binfmt-support"
echo "           bash scripts/register-binfmt-aarch64.sh"
echo "   and remember a 'wsl --shutdown' or an idle WSL timeout clears the rule."
exit 1
