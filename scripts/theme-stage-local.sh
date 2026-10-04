#!/bin/bash
# theme-stage-local.sh - download the Art Book Next theme set into the repo ON THE HOST
# and verify it against the sha256 ROCKNIX pins, so the theme is available without the
# board ever having to pull it (the board is compiling; SD I/O is what made GuiMenu.cpp
# thrash earlier today, so nothing heavy goes over ssh while a build is running).
#
#   bash scripts/theme-stage-local.sh             # fetch + verify (keeps the .tar.gz)
#   EXTRACT=1 bash scripts/theme-stage-local.sh   # also unpack into build/vendor/theme-stage
#
# Provenance: anthonycaccese/art-book-next-es is the "Batocera ES Edition" of the theme -
# its own README says it targets Batocera v40+, Knulli, ROCKNIX and RetroBat and is based
# on batocera-linux/batocera-emulationstation, i.e. the very fork we are now compiling.
# The revision and sha256 below are the pair ROCKNIX pins in
# projects/ROCKNIX/packages/ui/themes/es-theme-art-book-next/package.mk, and the same
# tarball already sits verified on the board at /root/art-book-next-<rev>.tar.gz -
# a matching sha256 here proves this is byte-for-byte the same artifact.
set -uo pipefail
REV=9a50ef366e750aabfab29e6915a2867607212971
SHA=7ee1e93f2c4e4f7385b78680ecfa3828acf12bc616e2111d23cc66a524231125
URL=https://github.com/anthonycaccese/art-book-next-es/archive/$REV.tar.gz
CDN=https://codeload.github.com/anthonycaccese/art-book-next-es/tar.gz/$REV
VENDOR=$(cd "$(dirname "$0")" && pwd)/vendor
T=art-book-next-$REV.tar.gz

mkdir -p "$VENDOR"
cd "$VENDOR" || exit 1

if [ -f "$T" ]; then
  echo "  already present: $T ($(stat -c %s "$T") bytes)"
else
  echo "=== download $URL ==="
  echo "  started $(date '+%T'); this streams (GitHub gives no Content-Length), progress is by bytes"
  # -L because github.com/.../archive/... redirects to codeload; --retry for the flaky
  # home wifi this board shares the uplink with; no --max-time per attempt because a
  # 200 MB theme on a laptop line can legitimately take several minutes
  if ! curl -sSL --retry 3 --retry-delay 5 --connect-timeout 20 -o "$T.part" "$CDN"; then
    echo "  !! download failed"; rm -f "$T.part"; exit 1
  fi
  mv "$T.part" "$T"
  echo "  done $(date '+%T'): $(stat -c %s "$T") bytes"
fi

echo "=== verify sha256 against ROCKNIX's PKG_SHA256 ==="
got=$(sha256sum "$T" | cut -d' ' -f1)
echo "  expected: $SHA"
echo "  got     : $got"
if [ "$got" != "$SHA" ]; then
  echo "  !! MISMATCH - not usable, delete $T and re-fetch"
  exit 1
fi
echo "  PASS - byte-identical to the artifact ROCKNIX pins and the one on /root of the board"

{
  echo "theme      : Art Book Next (Batocera ES Edition)"
  echo "upstream   : $URL"
  echo "revision   : $REV"
  echo "sha256     : $SHA   (ROCKNIX packages/ui/themes/es-theme-art-book-next/package.mk)"
  echo "size       : $(stat -c %s "$T") bytes"
  echo "staged at  : $(date '+%F %T')"
  echo "targets    : Batocera v40+, Knulli, ROCKNIX, RetroBat (per upstream README)"
  echo "compat     : formatVersion 7, <subset name=distribution> with batocera/rocknix/retrobat"
} > "$T.info"

echo "=== what is in it (top level + counts, no extraction) ==="
tar tzf "$T" 2>/dev/null | awk -F/ 'NF>2 {print $2}' | sort | uniq -c | sort -rn | head -12 | sed 's/^/  /'
echo "  entries: $(tar tzf "$T" 2>/dev/null | wc -l)"
if [ "${EXTRACT:-0}" = 1 ]; then
  echo "=== extracting to vendor/theme-stage ==="
  rm -rf theme-stage && mkdir -p theme-stage
  tar xzf "$T" -C theme-stage --strip-components=1 || { echo "  !! extract failed"; exit 1; }
  echo "  theme.xml present: $([ -f theme-stage/theme.xml ] && echo yes || echo NO)"
  echo "  du: $(du -sh theme-stage 2>/dev/null | cut -f1)"
fi
echo "=== ready. install on the board with scripts/k72-es-theme-install.sh (after phase A) ==="
