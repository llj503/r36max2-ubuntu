#!/bin/bash
# v20-prepack-check.sh - the last size reading came out as 7.3G, which is the WSL
# disk, not the rootfs (an inline variable got eaten again).  Measure for real and
# see what the weston install actually cost before packing.
set -uo pipefail
ROOT=/root/r36/rootfs
echo "  rootfs: $(du -sh "$ROOT" | cut -f1)"
echo "  biggest directories under it:"
du -sh "$ROOT"/* 2>/dev/null | sort -rh | head -8 | sed 's/^/    /'
echo "  var breakdown:"
du -sh "$ROOT"/var/* 2>/dev/null | sort -rh | head -6 | sed 's/^/    /'
echo "  apt cache: $(du -sh "$ROOT"/var/cache/apt 2>/dev/null | cut -f1), lists: $(ls "$ROOT"/var/lib/apt/lists 2>/dev/null | wc -l) files"
echo "  disk free in WSL: $(df -h / | tail -1)"
echo "  mounts inside the rootfs: $(cat /proc/mounts | grep -c "$ROOT")"
cat /proc/mounts | grep "$ROOT" | sed 's/^/    /'
