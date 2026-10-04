#!/bin/bash
# k72-vop-now.sh - test the "shared IRQ got killed as spurious" hypothesis against
# the state the board is in RIGHT NOW (it is wedged, so this is free evidence).
#
# vop_isr() begins with:
#     if (!pm_runtime_get_if_in_use(vop->dev)) return IRQ_NONE;
# and the VOP irq is shared with the IOMMU.  If every handler on a shared line
# returns IRQ_NONE repeatedly, the generic IRQ layer prints "irq N: nobody cared"
# and DISABLES the line - which would explain a permanently dead vblank that
# survives stopping the compositor and only clears on reboot.
#
# So: look for that message, read the runtime PM state of every display device, and
# watch whether the vop interrupt counter moves at all.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 150 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
echo "  host=$(hostname) uptime=$(cut -d. -f1 /proc/uptime)s weston=$(systemctl is-active weston)"
echo
echo "=== A) did the generic layer kill the irq? (the smoking gun) ==="
dmesg 2>/dev/null | grep -iE "nobody cared|disabling irq|too many warnings|handlers did not handle|irq .* none" | tail -10 | sed 's/^/     /'
echo "  matches in the whole journal this boot:"
journalctl -b -k --no-pager 2>/dev/null | grep -icE "nobody cared|disabling irq" | sed 's/^/     /'
journalctl -b -k --no-pager 2>/dev/null | grep -iE "nobody cared|disabling irq" | tail -4 | sed 's/^/     /'
echo
echo "=== B) the vop interrupt line and its neighbours ==="
grep -iE "vop|iommu|display" /proc/interrupts 2>/dev/null | sed 's/  */ /g' | sed 's/^/     /'
echo "  vop count sampled twice, 3s apart (weston=$(systemctl is-active weston)):"
v1=$(awk '/vop/{for(i=2;i<=NF;i++) if($i ~ /^[0-9]+$/) {print $i; exit}}' /proc/interrupts)
sleep 3
v2=$(awk '/vop/{for(i=2;i<=NF;i++) if($i ~ /^[0-9]+$/) {print $i; exit}}' /proc/interrupts)
echo "     vop irq count: $v1 -> $v2  (delta $((v2-v1)))"
echo
echo "=== C) runtime PM state of the display devices ==="
for d in /sys/devices/platform/ff400000.vop /sys/devices/platform/ff400000.vop/../*vop* /sys/devices/platform/*dsi* /sys/devices/platform/*display-subsystem*; do
  [ -d "$d" ] || continue
  echo "     $(basename $d): status=$(cat $d/power/runtime_status 2>/dev/null) usage=$(cat $d/power/usage_count 2>/dev/null) suspend_ms=$(cat $d/power/runtime_status 2>/dev/null)"
done
echo
echo "=== D) what does the driver think the CRTC is doing? ==="
mount -t debugfs none /sys/kernel/debug 2>/dev/null
if [ -r /sys/kernel/debug/dri/0/summary ]; then
  sed -n '1,60p' /sys/kernel/debug/dri/0/summary | sed 's/^/     /'
else
  echo "     (no debugfs summary)"
fi
echo
echo "=== E) stall messages right now ==="
echo "     total since boot: $(journalctl -b -k --no-pager 2>/dev/null | grep -cE 'vblank wait timed out|wait_for_vblanks|flip_done timed out')"
echo "     last one: $(journalctl -b -k --no-pager 2>/dev/null | grep -E 'vblank wait timed out|wait_for_vblanks' | tail -1 | cut -c1-90)"
EOS
echo "=== now-state check done ==="
