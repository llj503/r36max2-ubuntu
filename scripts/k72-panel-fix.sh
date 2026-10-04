#!/bin/bash
# k72-panel-fix.sh - the appended Kconfig entry never registered (probably
# because the file ends inside a `menu ... endmenu` block), so
# CONFIG_DRM_PANEL_GENERIC_DSI is absent and the panel driver would not build.
# Insert the entry *before* the last endmenu instead of appending.
set -uo pipefail
K=/root/r36/linux-7.2.8
F=$K/drivers/gpu/drm/panel/Kconfig

echo "=== last 14 lines of $F ==="
tail -14 "$F"
echo "=== structure counts: menu=$(grep -c '^menu ' "$F") if=$(grep -cE '^(if|menuif) ' "$F") end=$(grep -c '^end' "$F") ==="
grep -n "GENERIC_DSI" "$F" | head -3

if grep -q "DRM_PANEL_GENERIC_DSI" "$F"; then
  echo "  entry already present"
else
  # drop the stray append (everything after the last endmenu) if it exists
  awk '/^config DRM_PANEL_GENERIC_DSI/{exit} {print}' "$F" > "$F.tmp" && mv "$F.tmp" "$F"
  last_end=$(grep -n '^endmenu' "$F" | tail -1 | cut -d: -f1)
  echo "  inserting before line $last_end (last endmenu)"
  {
    head -n $((last_end - 1)) "$F"
    cat <<'KC'

config DRM_PANEL_GENERIC_DSI
	tristate "Generic DSI panel with a textual panel_description"
	depends on OF && MIPI_DSI
	help
	  Carried over from Rocknix: identifies the panel by the
	  panel_description string in the DT instead of a hard-coded list.
KC
    tail -n +"$last_end" "$F"
  } > "$F.tmp" && mv "$F.tmp" "$F"
fi

echo "=== verify placement ==="
grep -n -B2 -A6 "config DRM_PANEL_GENERIC_DSI" "$F" | head -20
echo "=== Makefile line ==="
grep -n "generic-dsi" "$K/drivers/gpu/drm/panel/Makefile"
echo "done (run scripts/config --enable DRM_PANEL_GENERIC_DSI + olddefconfig after the running build finishes)"
