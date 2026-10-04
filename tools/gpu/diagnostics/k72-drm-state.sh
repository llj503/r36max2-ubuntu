#!/bin/bash
# k72-drm-state.sh - is the display pipeline still stalled with weston dead, and
# what does the VOP think it is doing?  Also install kbd so we finally get chvt /
# fgconsole on this image (their absence is why "active vt" kept printing empty).
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 150 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
DEBIAN_FRONTEND=noninteractive apt-get install -y -q kbd >/dev/null 2>&1
echo "  kbd installed: chvt=$(command -v chvt || echo no) fgconsole=$(command -v fgconsole || echo no)"
echo "  fgconsole now: $(fgconsole 2>&1)"

echo
echo "=== warning cadence, 25 seconds with no compositor running ==="
A=$(journalctl -b --no-pager -k | grep -c "wait_for_vblanks")
E1=$(journalctl -b --no-pager -k | grep -c "flip_done timed out")
sleep 25
B=$(journalctl -b --no-pager -k | grep -c "wait_for_vblanks")
E2=$(journalctl -b --no-pager -k | grep -c "flip_done timed out")
echo "  wait_for_vblanks: $A -> $B (+$((B-A)))"
echo "  flip_done timed out: $E1 -> $E2 (+$((E2-E1)))"
echo "  last 3 rockchip-drm errors:"
journalctl -b --no-pager -k | grep "rockchip-drm" | tail -3 | sed 's/^/    /'

echo
echo "=== VOP / CRTC state ==="
mount -t debugfs none /sys/kernel/debug 2>/dev/null
if [ -e /sys/kernel/debug/dri/0/summary ]; then
  grep -A6 -E "crtc\[39\]|DSI-1|connector\[" /sys/kernel/debug/dri/0/summary 2>/dev/null | head -40 | sed 's/^/  /'
else
  echo "  no /sys/kernel/debug/dri (CONFIG_DRM_DEBUG?); trying sysfs instead"
fi
for p in /sys/class/drm/card0-DSI-1/status /sys/class/drm/card0-DSI-1/modes; do echo "  $p: $(cat $p 2>/dev/null | tr '\n' ' ')"; done
echo "  plane count: $(ls /sys/kernel/debug/dri/0/ 2>/dev/null | tr '\n' ' ')"
echo "  fb0: blank=$(cat /sys/class/graphics/fb0/blank 2>/dev/null) virt=($(cat /sys/class/graphics/fb0/virtual_size 2>/dev/null))"
echo "  console font/size: $(cat /sys/class/graphics/fb0/stride 2>/dev/null)"
EOS
echo "=== state check done ==="
