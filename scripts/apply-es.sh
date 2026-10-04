#!/bin/bash
# apply-es.sh - fold the EmulationStation work into a staging rootfs, so a reflash
# reproduces what only lived on the 64 GB card (see KNOWN-ISSUES: "ES 没进镜像").
#
#   R=/root/r36/rootfs bash scripts/apply-es.sh
#
# What this does NOT do: it does not build ES. The 117 MB binary is the one measured
# on the board, so it is taken from a staging dir and verified, the same way the
# out-of-tree modules are (see artifacts/prebuilt + v20-rootfs.sh).
set -euo pipefail
REPO=${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
R=${R:-/root/r36/rootfs}
ES=$REPO/packages/r36-emulationstation
# where the built emulationstation binary + theme live offline (gitignored)
STAGE=${ES_STAGE:-$REPO/artifacts/es}

echo "=== rootfs: $R ==="
[ -d "$R" ] || { echo "!! no staging rootfs at $R"; exit 1; }

echo "=== [1] launcher and input config ==="
mkdir -p "$R/usr/local/bin" "$R/root/es" "$R/root/.emulationstation/themes" "$R/root/roms/demo"
cp -f "$ES/r36-es"            "$R/usr/local/bin/r36-es"; chmod 755 "$R/usr/local/bin/r36-es"
cp -f "$ES/es-input-r36max2.cfg" "$R/root/.emulationstation/es_input.cfg"; chmod 644 "$R/root/.emulationstation/es_input.cfg"
# ES in this fork exits outright when es_systems.cfg is missing, which reads on a
# keyboard-less board as "ES is broken". Ship a valid list with no systems in it.
cp -f "$ES/es_systems.cfg"    "$R/root/.emulationstation/es_systems.cfg"; chmod 644 "$R/root/.emulationstation/es_systems.cfg"
bash -n "$R/usr/local/bin/r36-es" && echo "  r36-es parses"
python3 -c "import sys,xml.etree.ElementTree as T; T.parse(sys.argv[1])" \
  "$R/root/.emulationstation/es_input.cfg" && echo "  es_input.cfg parses"

echo "=== [2] the GUID must be this board's, not copied from Batocera ==="
# Batocera's retrogame_joypad entry has a/b and x/y swapped relative to our DT order;
# copying it silently trades A and B. Measured GUID via packages/gpu-demos/r36-sdljoy.c.
grep -q 'deviceGUID="19009b4d4b4800000111000000010000"' "$R/root/.emulationstation/es_input.cfg" \
  || { echo "!! es_input.cfg lost this board's GUID"; exit 1; }
# menu navigation only consumes left/up names or joystick1* axes; leftanalog* has no
# consumer in this fork at all, so without these two the stick cannot move the cursor.
for axis in joystick1left joystick1up; do
  grep -q "name=\"$axis\"" "$R/root/.emulationstation/es_input.cfg" \
    || { echo "!! es_input.cfg lost the $axis binding"; exit 1; }
done

echo "=== [3] the binary and the theme come from the verified staging dir ==="
[ -d "$STAGE" ] || { echo "!! 需要 $STAGE（放已验证的 emulationstation 二进制与主题）"; exit 1; }
[ -s "$STAGE/SHA256SUMS" ] || { echo "!! 缺 $STAGE/SHA256SUMS"; exit 1; }
( cd "$STAGE" && sha256sum -c --quiet SHA256SUMS ) || { echo "!! ES 暂存内容与 SHA256SUMS 不一致"; exit 1; }

if [ -f "$STAGE/emulationstation" ]; then
  install -m 755 "$STAGE/emulationstation" "$R/root/es/emulationstation"
  echo "  ES binary installed ($(stat -c %s "$R/root/es/emulationstation") B)"
else
  echo "!! $STAGE/emulationstation 不存在"; exit 1
fi
if [ -d "$STAGE/theme/art-book-next" ]; then
  cp -a "$STAGE/theme/art-book-next" "$R/root/.emulationstation/themes/"
  echo "  theme staged: $(find "$R/root/.emulationstation/themes/art-book-next" -name '*.xml' | wc -l) xml, \
$(find "$R/root/.emulationstation/themes/art-book-next" -name '*.png' | wc -l) png"
else
  echo "  !! 主题没暂存：es_settings.cfg 里 ThemeSet=art-book-next 会指空，退回默认主题"
fi

echo "=== [4] settings: theme name must resolve to a directory that is really there ==="
mkdir -p "$R/root/.emulationstation"
if [ ! -d "$R/root/.emulationstation/themes/art-book-next" ]; then
  echo "  (no theme staged - leaving es_settings.cfg untouched)"
else
  grep -q 'name="ThemeSet"' "$R/root/.emulationstation/es_settings.cfg" 2>/dev/null || \
    printf '<?xml version="1.0" encoding="UTF-8"?>\n<settings>\n\t<string name="ThemeSet" value="art-book-next" />\n</settings>\n' \
      > "$R/root/.emulationstation/es_settings.cfg"
  th=$(sed -n 's/.*ThemeSet" value="\([^"]*\)".*/\1/p' "$R/root/.emulationstation/es_settings.cfg" | head -1)
  [ -d "$R/root/.emulationstation/themes/$th" ] || { echo "!! ThemeSet=$th 但目录不存在"; exit 1; }
  echo "  ThemeSet=$th resolves"
fi

echo "=== [5] what still needs eyes, stated up front ==="
echo "  ES draws and the stick navigates (confirmed by eye on 2026-10-04 under"
echo "  'r36-es --kmsdrm'), but that was the card's build. After a reflash, re-run:"
echo "    tools/emulationstation/verify/es-smoke-device.sh   (bridge off first: it grabs the joypad)"
