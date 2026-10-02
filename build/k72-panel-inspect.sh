#!/bin/bash
# k72-panel-inspect.sh - two compile errors in the carried-over panel driver:
# hex2bin (missing include) and drm_panel_init (panel API rework).  Look at the
# code and at what 7.2's drm_panel.h actually offers before deciding the fix.
set -uo pipefail
K=/root/r36/linux-7.2.8
P=$K/drivers/gpu/drm/panel/panel-generic-dsi.c

echo "=== includes in the driver ==="
grep -n "^#include" "$P" | sed 's/^/  /'
echo "=== around hex2bin (line 204) ==="
sed -n '196,212p' "$P" | sed 's/^/  /'
echo "=== around drm_panel_init (line 693) ==="
sed -n '676,700p' "$P" | sed 's/^/  /'
echo "=== what does 7.2 drm_panel.h provide? ==="
grep -nE "^(int|void|struct drm_panel \*) *drm_panel_[a-z_]+\(" "$K/include/drm/drm_panel.h" | sed 's/^/  /'
grep -n "devm_drm_panel_add\|drm_panel_add\|drm_panel_init\|of_drm_find_panel\|drm_of_find_panel_or_bridge" "$K/include/drm/drm_panel.h" | sed 's/^/  /'
echo "=== how do in-tree DSI panels register themselves in 7.2? (sample) ==="
grep -nE "drm_panel_(add|init|register)|_component_enable|panel->funcs" "$K/drivers/gpu/drm/panel/panel-simple-dsi.c" 2>/dev/null | head -6
grep -nE "module_dsi_driver|\.probe|drm_panel_add" "$K/drivers/gpu/drm/panel/panel-simple.c" | tail -8
echo "=== does the DSI host bind via component or of_graph? ==="
grep -n "of_graph\|drm_of_find_panel" "$K/drivers/gpu/drm/rockchip/dw-mipi-dsi-rockchip.c" | head -5
echo "=== inspect done ==="
