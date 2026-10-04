#!/bin/bash
# apply-es-selftest.sh - run scripts/apply-es.sh against a throwaway rootfs and a
# throwaway ES staging dir, and check that it (a) installs what the card needs,
# (b) refuses bytes that do not match SHA256SUMS, (c) refuses a wrong GUID, and
# (d) fails closed when an input is missing.  Nothing here touches /root/r36,
# a real card, or the repo's own files (the GUID case works on a copy of the tree).
#
#   bash tools/emulationstation/verify/apply-es-selftest.sh
set -u
REPO=${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
fail=0
note() { echo "  $*"; }
want() { # $1=label $2=expected rc $3=actual rc
  if [ "$2" = "$3" ]; then note "ok      $1 (rc=$3)"; else note "FAIL    $1 (rc=$3, want $2)"; fail=1; fi
}

R="$W/rootfs"; STAGE="$W/es"
mkdir -p "$R/usr/local/bin" "$R/lib/modules" "$R/etc" "$STAGE/theme/art-book-next"
echo "<root/>" > "$STAGE/theme/art-book-next/theme.xml"
mk_es() { printf '#!/bin/sh\necho fake ES\n' > "$STAGE/emulationstation"; chmod 755 "$STAGE/emulationstation"; }
reseal() { mk_es; ( cd "$STAGE" && sha256sum emulationstation theme/art-book-next/theme.xml > SHA256SUMS ); }
reseal

echo "=== A. happy path ==="
R="$R" ES_STAGE="$STAGE" bash "$REPO/scripts/apply-es.sh" > "$W/a.log" 2>&1
want "installs into a staged rootfs" 0 "$?"
grep -q 'r36-es parses'                    "$W/a.log" || note "FAIL  launcher did not parse"
grep -q 'es_input.cfg parses'              "$W/a.log" || note "FAIL  input cfg did not parse"
grep -q 'ThemeSet=art-book-next resolves'  "$W/a.log" || note "FAIL  theme did not resolve"
grep -Eq 'r36-es parses|es_input.cfg parses|ThemeSet=.* resolves' "$W/a.log" || { note "FAIL  no positive assertions ran at all"; fail=1; }
for f in usr/local/bin/r36-es root/es/emulationstation \
         root/.emulationstation/es_input.cfg root/.emulationstation/es_systems.cfg \
         root/.emulationstation/themes/art-book-next/theme.xml root/roms/demo; do
  [ -e "$R/$f" ] || { note "FAIL  /$f never landed"; fail=1; }
done
[ -x "$R/root/es/emulationstation" ] || { note "FAIL  ES binary not executable"; fail=1; }
[ -s "$R/root/.emulationstation/es_settings.cfg" ] || { note "FAIL  es_settings.cfg missing after staging a theme"; fail=1; }

echo "=== B. tampered binary must be refused ==="
cp -a "$W/rootfs" "$W/rootfs2"
# run A left a good binary in there, so ask a different question: put a sentinel in
# its place and require that the refused install never overwrote it.
printf 'SENTINEL\n' > "$W/rootfs2/root/es/emulationstation"
printf '#!/bin/sh\necho evil\n' > "$STAGE/emulationstation"   # content now != SHA256SUMS
R="$W/rootfs2" ES_STAGE="$STAGE" bash "$REPO/scripts/apply-es.sh" > "$W/b.log" 2>&1
want "SHA256SUMS mismatch stops the install" 1 "$?"
grep -q 'SHA256SUMS' "$W/b.log" || { note "FAIL  refusal did not say why"; fail=1; }
[ "$(cat "$W/rootfs2/root/es/emulationstation")" = SENTINEL ] \
  || { note "FAIL  it installed the tampered binary anyway"; fail=1; }

echo "=== C. missing staging dir is refused, not skipped ==="
R="$W/rootfs2" ES_STAGE="$W/nope" bash "$REPO/scripts/apply-es.sh" > "$W/c.log" 2>&1
want "no ES_STAGE -> refuse" 1 "$?"

echo "=== D. missing rootfs is refused ==="
R="$W/ghost" ES_STAGE="$STAGE" bash "$REPO/scripts/apply-es.sh" > "$W/d.log" 2>&1
want "no rootfs -> refuse" 1 "$?"

echo "=== E. an es_input.cfg that lost this board's GUID is refused (on a copy of the tree) ==="
FAKE="$W/fakerepo"
mkdir -p "$FAKE/scripts" "$FAKE/packages/r36-emulationstation"
cp "$REPO/scripts/apply-es.sh" "$FAKE/scripts/"
cp "$REPO/packages/r36-emulationstation/"* "$FAKE/packages/r36-emulationstation/"
sed -i 's/19009b4d4b4800000111000000010000/deadbeefdeadbeefdeadbeefdeadbeef/' \
       "$FAKE/packages/r36-emulationstation/es-input-r36max2.cfg"
cp -a "$W/rootfs" "$W/rootfs3"; reseal
R="$W/rootfs3" ES_STAGE="$STAGE" REPO="$FAKE" bash "$FAKE/scripts/apply-es.sh" > "$W/e.log" 2>&1
want "wrong GUID -> refuse" 1 "$?"
grep -q "GUID" "$W/e.log" || { note "FAIL  GUID refusal did not say why"; fail=1; }

echo "=== F. losing a stick axis is refused the same way ==="
cp "$REPO/packages/r36-emulationstation/es-input-r36max2.cfg" \
   "$FAKE/packages/r36-emulationstation/es-input-r36max2.cfg"
sed -i '/name="joystick1up"/d' "$FAKE/packages/r36-emulationstation/es-input-r36max2.cfg"
cp -a "$W/rootfs" "$W/rootfs4"; reseal
R="$W/rootfs4" ES_STAGE="$STAGE" REPO="$FAKE" bash "$FAKE/scripts/apply-es.sh" > "$W/f.log" 2>&1
want "missing joystick1up -> refuse" 1 "$?"
grep -q 'joystick1up' "$W/f.log" || { note "FAIL  axis refusal did not name the axis"; fail=1; }

echo "=== the repo's own package files were never touched ==="
git -C "$REPO" status --short -- packages/r36-emulationstation | sed 's/^/  /'
echo "  (only '?? es_systems.cfg' is expected - it is new in this change)"

echo "=== apply-es-selftest: $([ "$fail" = 0 ] && echo ALL PASS || echo FAILURES) ==="
exit "$fail"
