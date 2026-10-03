#!/bin/bash
# k72-vt-recover.sh - weston is gone but the kernel still warns about vblank waits
# and fb0 reports blank state 4, so the console did not come back on its own.
# No chvt/console-utils on this image, so drive the VT ioctls directly and force a
# repaint of tty1 that the user can actually see.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 90 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
echo "=== current console state ==="
echo "  fgconsole: $(fgconsole 2>/dev/null || echo n/a)"
echo "  fb0 blank: $(cat /sys/class/graphics/fb0/blank 2>/dev/null)"
echo "  getty@tty1: $(systemctl is-active getty@tty1)"
echo "  active VTs: $(for t in 1 2 3 4 5 6; do [ -e /dev/tty$t ] && printf 'tty%s ' $t; done)"

echo
echo "=== 1) unblank the framebuffer console ==="
echo 0 > /sys/class/graphics/fb0/blank 2>&1 && echo "  wrote 0 to blank" || echo "  blank write failed"
echo "  fb0 blank now: $(cat /sys/class/graphics/fb0/blank)"

echo
echo "=== 2) VT_ACTIVATE(1) + VT_WAITACTIVE via ioctl (no chvt binary here) ==="
python3 - <<'PY'
import fcntl, os
VT_ACTIVATE, VT_WAITACTIVE = 0x4301, 0x4302
fd = os.open("/dev/tty0", os.O_RDWR)
for req, name in ((VT_ACTIVATE, "ACTIVATE"), (VT_WAITACTIVE, "WAITACTIVE")):
    try:
        fcntl.ioctl(fd, req, 1)
        print("  %-11s ok" % name)
    except OSError as e:
        print("  %-11s failed: %s" % (name, e))
os.close(fd)
PY

echo
echo "=== 3) force a visible repaint on tty1 ==="
printf '\033[H\033[J' > /dev/tty1 2>/dev/null
{
  echo ""
  echo "  ============================================"
  echo "   r36max2 console recovery $(date +%H:%M:%S)"
  echo "   kernel $(uname -r)  uptime $(cut -d' ' -f1 /proc/uptime)s"
  echo "   weston: $(systemctl is-active weston)   keymapper: $(systemctl is-active r36-keymapper)"
  echo "   if you can read this, the panel and fbcon are alive again"
  echo "  ============================================"
  echo ""
} > /dev/tty1 2>/dev/null && echo "  wrote to /dev/tty1" || echo "  /dev/tty1 write failed"
systemctl restart getty@tty1 2>/dev/null; sleep 1
echo "  getty restarted: $(systemctl is-active getty@tty1)"

echo
echo "=== 4) any remaining DRM flip staller? ==="
A=$(journalctl -b --no-pager -k | grep -c "wait_for_vblanks")
sleep 45
B=$(journalctl -b --no-pager -k | grep -c "wait_for_vblanks")
echo "  vblank warnings: $A -> $B (delta $((B-A)))"
echo "  fb0 blank after all that: $(cat /sys/class/graphics/fb0/blank)"
echo "  panel: $(cat /sys/class/drm/card0-DSI-1/status) $(cat /sys/class/drm/card0-DSI-1/modes 2>/dev/null | head -1)"
echo "  crtc state:"; grep -A3 "DSI-1" /sys/kernel/debug/dri/0/summary 2>/dev/null | head -12 | sed 's/^/    /'
EOS
echo "=== recovery attempted: ask the user what the panel shows ==="
