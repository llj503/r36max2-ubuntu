#!/bin/bash
# v20-tidy.sh - really clean the package cache inside the staging rootfs (the last
# attempt ran with an eaten variable and did nothing), then re-measure.
set -uo pipefail
ROOT=/root/r36/rootfs
echo "=== before: $(du -sh "$ROOT" | cut -f1), apt cache $(du -sh "$ROOT/var/cache/apt" | cut -f1), lists $(ls "$ROOT/var/lib/apt/lists" | wc -l) ==="
chroot "$ROOT" /usr/bin/env apt-get clean 2>&1 | tail -2 | sed 's/^/  apt-get clean: /'
rm -rf "$ROOT"/var/lib/apt/lists/* "$ROOT"/var/cache/apt/archives/*.deb 2>/dev/null
rm -rf "$ROOT"/var/tmp/* "$ROOT"/tmp/* 2>/dev/null
find "$ROOT/var/log" -type f -size +200k -printf "  trimming %p (%s B)\n" -exec truncate -s 0 {} \; 2>/dev/null | head -5
echo "=== after : $(du -sh "$ROOT" | cut -f1), apt cache $(du -sh "$ROOT/var/cache/apt" | cut -f1), lists $(ls "$ROOT/var/lib/apt/lists" 2>/dev/null | wc -l) ==="
echo "  var: $(du -sh "$ROOT/var" | cut -f1)   usr: $(du -sh "$ROOT/usr" | cut -f1)"
echo "  content to fit into the 2 GiB root partition: $(du -sm "$ROOT" | cut -f1) MiB"
