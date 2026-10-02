#!/bin/bash
# k72-timing-diag.sh - 7.2.8 boots and wlan0 works, but panel-generic-dsi aborts
# with "Failed to request panel display timing", so the panel never registers
# and the DSI host spams "cmd queue crashed".  Find which display-timing helper
# changed and what our DT node actually looks like.
set -uo pipefail
K=/root/r36/linux-7.2.8
P=$K/drivers/gpu/drm/panel/panel-generic-dsi.c

echo "=== the failing call site (search for the message) ==="
n=$(grep -n "Failed to request panel display timing" "$P" | cut -d: -f1)
echo "  message at line $n"
sed -n "$((n-32)),$((n+6))p" "$P" | sed 's/^/  /'

echo "=== which helpers does the driver use for timings? ==="
grep -nE "display_timing|of_parse_display_timing|display_of_get|drm_panel_get_display_timing|videomode|drm_display_mode" "$P" | head -20

echo "=== what does 7.2 offer in of_display_timing.h? ==="
grep -nE "^(struct display_timing|of_parse_display_timing|display_of_get[a-z_]*)" -A2 "$K/include/video/of_display_timing.h" | sed 's/^/  /'

echo "=== and in 6.12 (the version that worked) ==="
grep -nE "of_parse_display_timing|display_of_get" /root/r36/linux-6.12.79/include/video/of_display_timing.h | sed 's/^/  /'

echo "=== our DT panel node ==="
sed -n '/panel: panel@0/,/};/p' /mnt/e/ubuntu/board/rk3326-xifan-r36max2.dts | head -40 | sed 's/^/  /'
echo "=== timing subnodes anywhere in the dts? ==="
grep -nE "display-timings|timing@|panel-timing|clock-frequency|hactive" /mnt/e/ubuntu/board/rk3326-xifan-r36max2.dts | head -20
echo "=== diag done ==="
