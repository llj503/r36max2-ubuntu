#!/bin/bash
# k72-vop-compare.sh - narrow the "line_flag interrupt stopped forever" hypothesis
# space using the two kernel trees we already have, before spending another board
# reboot.  Questions answered here:
#   1. does vop_crtc_enable_vblank actually unmask the vsync/line interrupt, and
#      which register/bit does it touch on RK3326 (vop1 vs vop2)?
#   2. what changed between 6.12.79 and 7.2.8 in that driver (the A/B we are not
#      going to do on hardware yet)?
#   3. is there a "idle"/self-refresh path that can stop the VOP from generating
#      vsync when nothing changes - the one thing that matches "runs fine for ~20
#      minutes, then vblank never comes back"?
#   4. does our own DT (rk3326-xifan-r36max2.dts) leave the vop interrupt intact?
set -uo pipefail
K72=${K72:-/root/r36/linux-7.2.8}
K612=${K612:-/root/r36/linux-6.12.79}
V72=$K72/drivers/gpu/drm/rockchip/rockchip_drm_vop.c
V612=$K612/drivers/gpu/drm/rockchip/rockchip_drm_vop.c

echo "=== 1) vop_crtc_enable_vblank in 7.2.8 ==="
sed -n '1160,1200p' "$V72" | cat -n | awk '{printf "  %4d| %s\n", $1+1159, substr($0, index($0,$2))}'
echo
echo "=== 2) the isr: which bits it accepts, and where handle_vblank is called ==="
sed -n '1776,1830p' "$V72" | cat -n | awk '{printf "  %4d| %s\n", $1+1775, substr($0, index($0,$2))}'
echo
echo "=== 3) idle / self-refresh in 7.2.8 (grep) ==="
grep -n "idle\|IDR\|SELF_REFRESH\|standby\|dsp_hold" "$V72" | head -20 | sed 's/^/  /'
echo "  --- same grep in 6.12.79 ---"
grep -n "idle\|IDR\|SELF_REFRESH\|standby\|dsp_hold" "$V612" | head -20 | sed 's/^/  /'
echo
echo "=== 4) what differs in this driver between the two kernels ==="
echo "  file sizes: 6.12=$(wc -l < "$V612") lines  7.2=$(wc -l < "$V72") lines"
diff -u "$V612" "$V72" | grep -E "^[+-][^+-]" | grep -iE "vblank|line_flag|isr|idle|enable_vblank|REG_CFG|complete|wait" | head -30 | sed 's/^/  /'
echo
echo "=== 5) our board DTS: is the vop node + its interrupt untouched? ==="
D=/mnt/e/ubuntu/projects/r36max2/dt/rk3326-xifan-r36max2.dts
if [ -f "$D" ]; then
  grep -n -A6 -iE "vop|display-subsystem|dsi|panel" "$D" | grep -iE "vop|interrupt|status|dsi|panel|ports" | head -25 | sed 's/^/  /'
else
  echo "  (no $D)"
fi
echo
echo "=== 6) known-fixes search: does 7.2 ship a stable fix list mention? ==="
ls "$K72/Documentation/process/changes.rst" >/dev/null 2>&1 && echo "  (kernel doc present)"
grep -rn "wait_for_vblanks\|flip_done timed out" "$K72/drivers/gpu/drm/drm_crtc_helper.c" 2>/dev/null | head -5 | sed 's/^/  /'
