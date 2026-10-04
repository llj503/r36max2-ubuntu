#!/bin/bash
# k72-panel-dump.sh - show everything needed to port panel-generic-dsi.c to the
# 7.2 drm_panel API (devm_drm_panel_alloc replaces drm_panel_init).
set -uo pipefail
P=/root/r36/linux-7.2.8/drivers/gpu/drm/panel/panel-generic-dsi.c

echo "=== symbols of interest (line numbers) ==="
grep -nE "struct [a-z_]*dsi[a-z_]* \{|^struct |devm_kzalloc|devm_drm_panel|drm_panel_init|drm_panel_add|_probe\(|container_of|->panel\b" "$P" | head -30

echo
echo "=== the panel struct member + its container ==="
awk '/^struct .*\{/{name=$2; buf=""; inb=1} inb{buf=buf"\n"$0} inb&&/^\};/{ if (buf ~ /struct drm_panel/) print name buf; inb=0}' "$P" | head -40

echo
echo "=== probe function (from its signature to drm_panel_add) ==="
awk '/_probe\(struct mipi_dsi_device|^static int .*probe\(/{f=1} f{print NR": "$0} /drm_panel_add/{if(f)exit}' "$P" | head -60
echo "=== dump done ==="
