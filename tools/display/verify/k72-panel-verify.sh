#!/bin/bash
# k72-panel-verify.sh - confirm __devm_drm_panel_alloc's failure convention
# (ERR_PTR vs NULL) and that ctx->dev still gets set, then build the panel +
# a fresh Image.
set -uo pipefail
K=/root/r36/linux-7.2.8
P=$K/drivers/gpu/drm/panel/panel-generic-dsi.c

echo "=== __devm_drm_panel_alloc implementation ==="
awk '/^void \*__devm_drm_panel_alloc/,/^}/' "$K/drivers/gpu/drm/drm_panel.c" | sed 's/^/  /'
echo "=== does probe still set ctx->dev? ==="
grep -n "ctx->dev" "$P" | head -5
echo "=== build ==="
cd "$K" || exit 1
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)" Image 2>&1 | \
  grep -E "error|warning:|LD|Image|\.ko" | tail -14
ls -l arch/arm64/boot/Image | sed 's/^/  /'
echo "  panel object: $(ls -l drivers/gpu/drm/panel/panel-generic-dsi.o 2>/dev/null | awk '{print $5" bytes"}')"
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_MOD_PATH=/root/r36/out72 modules_install 2>&1 | tail -2
echo "=== verify done ==="
