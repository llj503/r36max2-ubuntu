#!/bin/bash
# k72-vop-read-code.sh - print the exact kernel code at the two warning sites so the
# diagnosis is anchored to real lines, not to my memory of what the Rockchip VOP
# driver does.  Sites from the live stack traces:
#   rockchip_drm_vop.c:1602  vop_crtc_atomic_flush+0x2b8/0x2c8
#   drm_atomic_helper.c:1921 drm_atomic_helper_wait_for_vblanks
# and the machinery behind them (what completion/irq the wait depends on).
set -uo pipefail
K72=${K72:-/root/r36/linux-7.2.8}
K612=${K612:-/root/r36/linux-6.12.79}
V=$K72/drivers/gpu/drm/rockchip/rockchip_drm_vop.c

echo "=== kernel trees ==="
for d in "$K72" "$K612"; do echo "  $d : $(head -5 "$d/Makefile" 2>/dev/null | awk '/^VERSION|^PATCHLEVEL|^SUBLEVEL/{printf "%s ", $0}')"; done
echo
echo "=== rockchip_drm_vop.c:1560-1625 (the flush that never returns) ==="
sed -n '1560,1625p' "$V" | cat -n | awk '{printf "  %4d| %s\n", $1+1559, substr($0, index($0,$2))}' 2>/dev/null | head -70
echo
echo "=== what does that wait depend on? (vop_crtc_wait_for_update + its completion) ==="
grep -n "vop_crtc_wait_for_update\|wait_for_completion\|complete(\|COMPLETION\|busy_wait\|vop_crtc_enable_vblank\|disable_vblank" "$V" | head -30 | sed 's/^/  /'
echo
echo "=== the vblank interrupt path: who signals it ==="
grep -n "IRQ_LINE_FLAG\|irq_handler\|vop_isr\|VP_SET_REG\|REG_CFG\|fspck\|dclk\|wait_for_vblank" "$V" | head -20 | sed 's/^/  /'
echo
echo "=== drm_atomic_helper.c:1900-1935 (the helper that timed out) ==="
sed -n '1900,1935p' "$K72/drivers/gpu/drm/drm_atomic_helper.c" | cat -n | awk '{printf "  %4d| %s\n", $1+1899, substr($0, index($0,$2))}'
echo
echo "=== diff the same function between 6.12.79 and 7.2.8 (what changed under us) ==="
V2=$K612/drivers/gpu/drm/rockchip/rockchip_drm_vop.c
if [ -f "$V2" ]; then
  diff -u "$V2" "$V" | grep -E "^[+-]" | grep -iE "vblank|complete|wait|irq|busy|REG_CFG|enable" | head -40 | sed 's/^/  /'
  echo "  (diff lines shown above; full diff is $(diff "$V2" "$V" | wc -l) lines)"
else
  echo "  no 6.12 vop file at $V2"
fi
