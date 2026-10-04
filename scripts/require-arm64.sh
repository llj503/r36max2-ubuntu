#!/bin/bash
# require-arm64.sh - make sure this host can actually execute the arm64 binaries that
# live in a staging rootfs, before any script starts chrooting into it.
#
#   bash scripts/require-arm64.sh /root/r36/rootfs
#
# Why this exists as its own step: WSL's VM stops whenever the distro goes idle, and a
# binfmt rule written to /proc/sys/fs/binfmt_misc does not survive that.  So "my chroot
# worked an hour ago" is not a fact you can rely on mid-pipeline.  Without a handler
# every chroot call fails with Exec format error, and the scripts that used to ignore
# that still wrote their config files and printed DONE over an empty rootfs.
set -u
REPO=${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
ROOT=${1:?usage: require-arm64.sh <rootfs-dir>}

ok() { chroot "$ROOT" /bin/sh -c 'uname -m' 2>/dev/null | grep -q aarch64; }

if ok; then echo "  arm64 chroot works in $ROOT"; exit 0; fi
echo "  no arm64 handler yet - registering the packaged rule"
bash "$REPO/scripts/register-binfmt-aarch64.sh" >/dev/null 2>&1 || true
if ok; then echo "  arm64 chroot works now ($(chroot "$ROOT" /bin/sh -c 'uname -m'))"; exit 0; fi

echo "!! still cannot execute arm64 in a chroot."
echo "   check:  ls /proc/sys/fs/binfmt_misc/            (want qemu-aarch64)"
echo "           apt-get install qemu-user-static binfmt-support"
echo "           bash scripts/register-binfmt-aarch64.sh"
echo "   and remember a 'wsl --shutdown' or an idle WSL timeout clears the rule."
exit 1
