#!/bin/bash
# k72-vop-irqwatch.sh - localise where the VOP's line_flag (vblank) interrupt dies.
#
# The helper that times out does exactly three things: drm_crtc_vblank_get()
# (=> vop_crtc_enable_vblank), remember drm_crtc_vblank_count(), then wait for the
# count to move.  The count only moves in vop_isr().  So instead of theorising about
# weston, watch the interrupt itself under each state and use r36-flipprobe as an
# independent vblank liveliness meter (it measures real flip-completion latency).
#
# MUST be run on a fresh boot (the panel has to start un-wedged).
#
# IRQ name on this SoC is the vop device node name (ff400000.vop on RK3326), so the
# samples below grep for "vop" in /proc/interrupts rather than guessing a label.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 420 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
export XDG_RUNTIME_DIR=/run/wayland WAYLAND_DISPLAY=wayland-0
irq() { awk '/vop/{for(i=2;i<=NF;i++) if($i ~ /^[0-9]+$/) {print $i; exit}}' /proc/interrupts; }
vopline() { grep vop /proc/interrupts | head -2 | sed 's/  */ /g'; }
note() { echo "  -- $1: vop_irq_count=$(irq)   stall_total=$(journalctl -b -k --no-pager 2>/dev/null | grep -cE 'vblank wait timed out|wait_for_vblanks')"; }

mount -t debugfs none /sys/kernel/debug 2>/dev/null
echo "  host=$(hostname) uptime=$(cut -d. -f1 /proc/uptime)s   (fresh boot required)"
echo "  vop interrupt line(s): $(vopline)"
echo "  weston=$(systemctl is-active weston)  fgvt=$(fgconsole 2>/dev/null)"
echo
echo "=== stage 0: bare console, nobody has done a modeset ==="
systemctl stop weston 2>/dev/null; sleep 3
note "console idle"
a=$(irq); sleep 3; b=$(irq)
echo "     count delta over 3s idle console: $((b-a))   (0 is normal: vblank refcount is off)"
echo "  flipprobe (does a page flip complete?):"
timeout 60 /usr/local/bin/r36-flipprobe 8 20 2>&1 | tail -3 | sed 's/^/     /'
note "after stage-0 flips"

echo
echo "=== stage 1: weston up (it does an atomic modeset) ==="
systemctl start weston; sleep 6
note "weston idle"
a=$(irq); sleep 3; b=$(irq); echo "     delta over 3s with weston idle: $((b-a))"
(setsid timeout 8 weston-simple-egl >/tmp/egl-irq.log 2>&1 &)
sleep 2
a=$(irq); sleep 4; b=$(irq)
echo "     delta over 4s WHILE a client repaints: $((b-a))   (expect tens: ~60/s while flipping)"
note "after egl repaint burst"
echo "  stall messages in the last 60s: $(journalctl -b -k --no-pager --since '-60 seconds' 2>/dev/null | grep -cE 'vblank wait timed out|wait_for_vblanks')"

echo
echo "=== stage 2: VOP register state from debugfs (is the vsync interrupt enabled?) ==="
if [ -r /sys/kernel/debug/dri/0/summary ]; then
  awk '/vop@|crtc|^state|^|^ *regs/{p=1} p' /sys/kernel/debug/dri/0/summary 2>/dev/null | head -45 | sed 's/^/     /'
else
  echo "     (no /sys/kernel/debug/dri/0/summary)"
fi

echo
echo "=== stage 3: stop weston, then a plain SDL kmsdrm modeset (this is what hung) ==="
systemctl stop weston 2>/dev/null; sleep 3
note "before sdl"
timeout 45 systemd-run --unit=vopwatch --wait --collect --no-ask-password \
  -p Type=oneshot -p TTYPath=/dev/tty1 -p StandardInput=tty -p TTYVTDisallocate=no \
  -p Environment=HOME=/root -p Environment=XDG_VTNR=1 -p TimeoutStartSec=35 \
  /bin/sh -c "/usr/local/bin/r36-sdlprobe kmsdrm > /tmp/sdl-irq.log 2>&1; echo rc=\$? >> /tmp/sdl-irq.log" >/dev/null 2>&1
echo "     systemd-run rc=$?"
sed 's/^/     /' /tmp/sdl-irq.log 2>/dev/null | head -14
note "after sdl attempt"
echo "  stall messages since the sdl attempt: $(journalctl -b -k --no-pager --since '-90 seconds' 2>/dev/null | grep -cE 'vblank wait timed out|wait_for_vblanks')"
echo "  vop line now: $(vopline)"
echo
echo "=== verdict inputs ==="
echo "  if the count was moving in stage 1 (repaint) but is frozen now, the modeset"
echo "  in stage 3 is what killed the interrupt - and the debugfs register dump above"
echo "  shows whether the vsync/line interrupt enable bit is still set."
echo "  giving weston back the panel:"
systemctl start weston; sleep 4
echo "  weston=$(systemctl is-active weston)"
EOS
echo "=== irqwatch done ==="
