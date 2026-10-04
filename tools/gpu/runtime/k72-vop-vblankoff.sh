#!/bin/bash
# k72-vop-vblankoff.sh - test the most likely root cause without rebuilding anything.
#
# Facts that line up:
#   * drm_atomic_helper_wait_for_vblanks() hangs => the FS/vblank interrupt never
#     arrives, although the VOP is runtime-PM active with dclk running.
#   * the ONLY thing that clears the FS interrupt enable is vop_crtc_disable_vblank().
#   * DRM calls disable_vblank() from a delayed work, and that delay is a tunable:
#     /sys/module/drm/parameters/vblankoffdelay = 5000 ms on this kernel.
# So: set vblankoffdelay=0 (never auto-disable the vblank irq) and run the exact
# reproduction that wedged the panel minutes ago (a plain SDL2 kmsdrm modeset from a
# service owning the VT).  If it no longer wedges, we have both the diagnosis and a
# boot-time mitigation (kernel cmdline drm.vblankoffdelay=0) - and only then is it
# worth rebuilding the kernel with kprobes to prove the race in code.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 300 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
irq() { awk '/vop/{for(i=2;i<=NF;i++) if($i ~ /^[0-9]+$/) {print $i; exit}}' /proc/interrupts; }
stall() { journalctl -b -k --no-pager 2>/dev/null | grep -cE 'vblank wait timed out|wait_for_vblanks|flip_done timed out'; }

echo "  host=$(hostname) uptime=$(cut -d. -f1 /proc/uptime)s stall=$(stall)  (need a fresh boot)"
echo "  before: vblankoffdelay=$(cat /sys/module/drm/parameters/vblankoffdelay) debug=$(cat /sys/module/drm/parameters/debug)"
echo 0 > /sys/module/drm/parameters/vblankoffdelay
echo "  after : vblankoffdelay=$(cat /sys/module/drm/parameters/vblankoffdelay)"

echo
echo "=== sanity: are interrupts flowing at all right now? (2s sample) ==="
a=$(irq); sleep 2; b=$(irq); echo "     vop irq $a -> $b (delta $((b-a)))"

echo
echo "=== reproduce: SDL kmsdrm modeset (this wedged it ~60s in, twice) ==="
c=$(irq)
timeout 90 systemd-run --unit=vbo --wait --collect --no-ask-password \
  -p Type=oneshot -p TTYPath=/dev/tty1 -p StandardInput=tty -p TTYVTDisallocate=no \
  -p Environment=HOME=/root -p Environment=XDG_VTNR=1 -p TimeoutStartSec=60 \
  /bin/sh -c "/usr/local/bin/r36-sdlprobe kmsdrm > /tmp/vbo.log 2>&1; echo rc=\$? >> /tmp/vbo.log" >/dev/null 2>&1
echo "     systemd-run rc=$?  (0 = it finished on its own = no hang)"
sed 's/^/     /' /tmp/vbo.log 2>/dev/null | head -14
d=$(irq)
echo "     vop irq during the attempt: $c -> $d (delta $((d-c)))"
echo "     stall messages now: $(stall)"

echo
echo "=== does legacy page flipping still complete? (independent vblank meter) ==="
systemctl stop weston 2>/dev/null; sleep 2
timeout 60 /usr/local/bin/r36-flipprobe 12 20 2>&1 | tail -2 | sed 's/^/     /'
echo "     stall messages now: $(stall)"

echo
echo "=== and the real use case: weston + a GL client for 30s ==="
systemctl start weston; sleep 5
(setsid timeout 25 weston-simple-egl >/tmp/egl-vbo.log 2>&1 &)
sleep 20
e=$(irq); sleep 3; f=$(irq)
echo "     vop irq while repainting: $e -> $f (delta $((f-e)))  <- expect ~180 (60Hz x 3s)"
echo "     weston=$(systemctl is-active weston)  stall=$(stall)"
echo "     weston's own complaints: $(journalctl -u weston --no-pager --since '-60 seconds' 2>/dev/null | grep -cE 'Device or resource busy|repaint-flush failed')"
echo
echo "  VERDICT INPUTS: stall count stayed 0, weston had no EBUSY, and the vop irq"
echo "  count moved while repainting => vblankoffdelay=0 removed the wedge."
EOS
echo "=== vblankoffdelay experiment done ==="
