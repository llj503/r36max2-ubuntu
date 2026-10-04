#!/bin/bash
# k72-vop-blankevidence.sh - is the console screen blanker the thing that kills the
# VOP's frame-start interrupt?  The two wedges both appeared ~20-23 minutes into a
# weston session, which is suspiciously close to a timer, and the kernel stack that
# kept faulting was drm_fb_helper_damage_work - i.e. the *console* is drawing
# through DRM's fbdev emulation and can therefore issue DPMS commits on a CRTC that
# weston believes it owns.
#
# Cheap things to look at on the ALREADY wedged machine, in one pass:
#   - fb0 blank state and dpms right now
#   - the console blank timeout actually in effect
#   - the VOP's runtime PM status (right address for RK3326: ff460000.vop)
#   - dclk/vop clock state from clk_summary
#   - time from boot to the FIRST stall message (does it match the blank timer?)
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 150 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
echo "  host=$(hostname) uptime=$(cut -d. -f1 /proc/uptime)s"
echo
echo "=== fb0 / console blanking ==="
for f in /sys/class/graphics/fb0/blank /sys/class/graphics/fb0/dpms /sys/class/graphics/fb0/modes; do
  echo "     $f = $(cat $f 2>/dev/null || echo absent)"
done
echo "     /sys/module/kernel/parameters/consoleblank = $(cat /sys/module/kernel/parameters/consoleblank 2>/dev/null || echo 'not exposed')"
echo "     cmdline: $(cat /proc/cmdline)"
echo "     vt global states: $(for d in /sys/class/vtconsole/vtcon*; do [ -e "$d/state" ] && echo "$(basename $d)=$(cat $d/state)"; done | tr '\n' ' ')"
echo "     getty on tty1: $(systemctl is-active getty@tty1.service)   fgvt=$(fgconsole 2>/dev/null)"
echo
echo "=== VOP runtime PM (RK3326 vop is ff460000.vop, not ff400000) ==="
for d in /sys/devices/platform/ff460000.vop /sys/devices/platform/ff450000.dsi /sys/devices/platform/ff460f00.iommu /sys/devices/platform/ff461000.iommu; do
  [ -d "$d" ] || continue
  echo "     $(basename $d): status=$(cat $d/power/runtime_status 2>/dev/null) usage=$(cat $d/power/runtime_usage 2>/dev/null || cat $d/power/usage_count 2>/dev/null) autosuspend_ms=$(cat $d/power/autosuspend_delay_ms 2>/dev/null)"
done
echo
echo "=== clocks (is dclk still running?) ==="
mount -t debugfs none /sys/kernel/debug 2>/dev/null
if [ -d /sys/kernel/debug/clk ]; then
  grep -iE "dclk_vop|aclk_vop|vop|dsiclk|pclk_dsi" /sys/kernel/debug/clk/clk_summary 2>/dev/null | head -12 | sed 's/^/     /'
else
  echo "     (no /sys/kernel/debug/clk - debugfs mount status: $(mount | grep -c debugfs))"
fi
echo
echo "=== boot time vs the FIRST stall message ==="
up=$(cut -d. -f1 /proc/uptime)
boot=$(awk '{print $1}' /proc/uptime)
first=$(journalctl -b -k --no-pager 2>/dev/null | grep -m1 -E "wait_for_vblanks|vblank wait timed out" | cut -d' ' -f1-3)
echo "     uptime now: ${up}s   first stall line: ${first:-none}"
journalctl -b -k --no-pager 2>/dev/null | grep -m1 -E "wait_for_vblanks|vblank wait timed out" | sed 's/^/     /'
echo "     (compare that timestamp against boot: 10:28-era behaviour is documented in the repo)"
echo
echo "=== did anything blank around then? ==="
journalctl -b --no-pager 2>/dev/null | grep -iE "blank|dpms|saver|console" | tail -6 | sed 's/^/     /'
EOS
echo "=== blank-evidence done ==="
