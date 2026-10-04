#!/bin/bash
# Install the verified expand script into the rootfs and re-pack the image.
set -eu
ROOT=/root/r36/rootfs
SRC=/mnt/e/ubuntu/build
cp -f "$SRC/r36-expand-root" "$ROOT/usr/local/sbin/r36-expand-root"
cp -f "$SRC/r36-finish-expand" "$ROOT/usr/local/sbin/r36-finish-expand"
chmod 755 "$ROOT/usr/local/sbin/"r36-*
sh -n "$ROOT/usr/local/sbin/r36-expand-root" && echo "syntax ok"
grep -c partx "$ROOT/usr/local/sbin/r36-expand-root"
bash "$SRC/pack-v10.sh" 2>&1 | tail -10
