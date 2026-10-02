#!/bin/bash
# k72-panel-api.sh - find (1) where hex2bin is declared in 7.2 and (2) the
# replacement for drm_panel_init(), by reading drm_panel.h and a driver that
# already uses the new API.
set -uo pipefail
K=/root/r36/linux-7.2.8
cd "$K" || exit 1

echo "=== hex2bin declaration ==="
grep -rn "hex2bin" include/linux/*.h | head -5

echo "=== drm_panel.h: the panel object and its registration API ==="
grep -nE "struct drm_panel \{|(funcs|connector|display)|devm_|drm_panel_(new|create|init|add|register|alloc)" include/drm/drm_panel.h | head -30

echo "=== a driver that already uses the new API (grep for the replacement) ==="
grep -rln "drm_panel_init" drivers/gpu/drm/panel/ | head -5
echo "  --- how does panel-simple-dsi/otm5000a register now:"
for f in drivers/gpu/drm/panel/panel-simple.c drivers/gpu/drm/panel/panel-orisetek-ota5639.c drivers/gpu/drm/panel/panel-raydium-rm67191.c; do
  [ -e "$f" ] || continue
  echo "  == $f"
  grep -nE "drm_panel|panel->funcs|_component_ops|drm_panel_add" "$f" | tail -8 | sed 's/^/     /'
done

echo "=== kernel doc / changelog hint for the rework ==="
grep -rn "drm_panel" Documentation/gpu/drm-internals.rst 2>/dev/null | head -5
echo "=== struct drm_panel definition ==="
sed -n "$(grep -n '^struct drm_panel {' include/drm/drm_panel.h | head -1 | cut -d: -f1),+28p" include/drm/drm_panel.h | sed 's/^/  /'
echo "=== api probe done ==="
