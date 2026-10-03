#!/bin/bash
# k72-vop-kprobe.sh - instrument the exact functions that decide whether the VOP's
# frame-start (vblank) interrupt is on, and reproduce the stall in ~60 s instead of
# waiting 20+ minutes for it to happen by itself.
#
# What we know already (measured this session):
#   - IRQ 27 is shared: ff460f00.iommu + ff460000.vop, and its count FREEZES while
#     weston is alive and wants to repaint (63799 -> 63799 over 3 s).
#   - VOP runtime PM = active, dclk_vopb = 62.16 MHz running, consoleblank = 0,
#     and the generic layer never printed "nobody cared" -> not runtime suspend,
#     not a clock, not the spurious-IRQ killer.
#   - the only place that clears the FS interrupt enable is vop_crtc_disable_vblank().
# So the question this answers: at the moment the pipeline dies, was the last thing
# that happened a disable_vblank() with no matching enable, or does the interrupt
# simply stop being asserted by hardware while the driver still thinks it is armed?
#
# Run this on a FRESH BOOT (the pipeline has to start un-wedged).
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 420 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
T=/sys/kernel/debug/tracing
mount -t debugfs none /sys/kernel/debug 2>/dev/null
[ -d "$T" ] || { echo "  !! no tracefs at $T - cannot run this experiment"; exit 1; }
echo "  host=$(hostname) uptime=$(cut -d. -f1 /proc/uptime)s weston=$(systemctl is-active weston)  (fresh boot required)"
irq() { awk '/vop/{for(i=2;i<=NF;i++) if($i ~ /^[0-9]+$/) {print $i; exit}}' /proc/interrupts; }

echo "=== [1] check the symbols are actually kprovable ==="
for f in vop_crtc_enable_vblank vop_crtc_disable_vblank vop_isr vop_crtc_atomic_flush; do
  if grep -qw "$f" /proc/kallsyms 2>/dev/null; then
    echo "     $f: $(grep -w "$f" /proc/kallsyms | head -1 | awk '{print $1, $3}')"
  else
    echo "     $f: NOT IN kallsyms (inlined or stripped) - probe will be skipped"
  fi
done

echo "=== [2] arm kprobes ==="
cd "$T" || exit 1
echo 0 > tracing_on 2>/dev/null
echo > trace 2>/dev/null
echo 8192 > buffer_size_kb 2>/dev/null
for p in vop_en vop_dis vop_isr vop_flush; do echo > kprobe_events 2>/dev/null; done
echo 'p:vop_en vop_crtc_enable_vblank' >> kprobe_events 2>/dev/null && echo "     vop_en armed"
echo 'p:vop_dis vop_crtc_disable_vblank' >> kprobe_events 2>/dev/null && echo "     vop_dis armed"
echo 'p:vop_isr vop_isr' >> kprobe_events 2>/dev/null && echo "     vop_isr armed"
echo 1 > events/kprobes/enable 2>/dev/null
echo $(date +%T) > /tmp/kprobe-started

echo "=== [3] baseline: healthy page flips (ISR must appear in the trace) ==="
systemctl stop weston 2>/dev/null; sleep 3
echo 1 > tracing_on 2>/dev/null
a=$(irq)
timeout 60 /usr/local/bin/r36-flipprobe 10 20 2>&1 | tail -2 | sed 's/^/     /'
b=$(irq); sleep 1; echo 0 > tracing_on
echo "     vop irq count: $a -> $b (delta $((b-a)))"
echo "     probe hits in this window: $(grep -c '' trace)"
grep -oE "vop_en|vop_dis|vop_isr" trace | sort | uniq -c | sed 's/^/     /'
echo 0 > trace; echo 1 > tracing_on

echo "=== [4] reproduce fast: plain SDL kmsdrm modeset (this is what hung before) ==="
c=$(irq)
timeout 70 systemd-run --unit=vopkb --wait --collect --no-ask-password \
  -p Type=oneshot -p TTYPath=/dev/tty1 -p StandardInput=tty -p TTYVTDisallocate=no \
  -p Environment=HOME=/root -p Environment=XDG_VTNR=1 -p TimeoutStartSec=40 \
  /bin/sh -c "/usr/local/bin/r36-sdlprobe kmsdrm > /tmp/sdl-kb.log 2>&1; echo rc=\$? >> /tmp/sdl-kb.log" >/dev/null 2>&1
echo "     systemd-run rc=$?"
head -12 /tmp/sdl-kb.log 2>/dev/null | sed 's/^/     /'
d=$(irq); echo 0 > tracing_on
echo "     vop irq count: $c -> $d (delta $((d-c)))   <-- 0 means no interrupt at all during the attempt"

echo "=== [5] the trace around the death (last 25 lines) ==="
tail -25 "$T/trace" 2>/dev/null | sed 's/^/     /'
echo "     call tally: $(grep -oE 'vop_en|vop_dis|vop_isr' "$T/trace" 2>/dev/null | sort | uniq -c | tr '\n' ' ')"

echo "=== [6] what does the driver say about the connector/CRTC pairing? ==="
if [ -r /sys/kernel/debug/dri/0/summary ]; then
  grep -A12 -iE "^Connector|DSI-1" /sys/kernel/debug/dri/0/summary 2>/dev/null | head -28 | sed 's/^/     /'
  echo "     --- CRTC state ---"
  grep -A10 -iE "^crtc|^ *crtc" /sys/kernel/debug/dri/0/summary 2>/dev/null | head -22 | sed 's/^/     /'
else
  echo "     (no /sys/kernel/debug/dri/0/summary; cards present: $(ls /sys/kernel/debug/dri 2>/dev/null | tr '\n' ' '))"
fi
echo "     stall messages now: $(journalctl -b -k --no-pager 2>/dev/null | grep -cE 'vblank wait timed out|wait_for_vblanks')"
echo
echo "  cleaning up kprobes"
echo 0 > "$T/events/kprobes/enable" 2>/dev/null
echo > "$T/kprobe_events" 2>/dev/null
echo 1 > "$T/tracing_on" 2>/dev/null
EOS
echo "=== kprobe experiment done ==="
