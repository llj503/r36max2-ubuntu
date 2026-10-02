#!/bin/bash
# Find the card's BOOT partition (it now has r36-boot.txt) and archive + print it.
set -uo pipefail
TS=$(date +%Y%m%d-%H%M%S)
mkdir -p /e/ubuntu/logs
found=0
for d in c d e f g h i j k l m n; do
  for f in "/$d/r36-boot.txt"; do
    if [ -f "$f" ]; then
      found=1
      cp -f "$f" "/e/ubuntu/logs/r36-boot-$TS.txt"
      echo "########## $f  ($(stat -c %s "$f") bytes) -> logs/r36-boot-$TS.txt"
      cat "$f"
    fi
  done
done
[ "$found" = 1 ] || { echo "no r36-boot.txt found on any drive; volumes present:"; ls -d /?/ 2>/dev/null | head -20; }
ls -la /e/ubuntu/logs/ | tail -3
