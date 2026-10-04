#!/bin/bash
# require-arm64.sh - make sure this host can actually execute the arm64 binaries that
# live in a staging rootfs, before any script starts chrooting into it.
#
#   bash scripts/require-arm64.sh "${BUILD}/image/system"
#
# Why this exists as its own step, called more than once: the binfmt rule is runtime
# state in /proc, and this WSL instance has no systemd as PID 1 (`systemctl` answers
# "Host is down"), so neither systemd-binfmt nor binfmt-support restores the rule when
# the VM comes back - an idle WSL timeout, or a `wsl --shutdown`, silently clears it.
# Measured 2026-10-04: inside one rootfs-apt run the rule was there for the dpkg step
# and gone by the account-creation chroot (Exec format error), and the old scripts that
# ignored that failure still wrote their config files and printed DONE over an empty
# rootfs.  Call this before every phase that execs out of the rootfs; the fast path is
# one `chroot ... uname -m` and returns 0.
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
