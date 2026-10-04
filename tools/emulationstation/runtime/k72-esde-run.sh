#!/bin/bash
# k72-esde-run.sh - does the ES-DE AppImage actually get a GL context and a window on
# this board?  --version already proved the binary loads against Ubuntu 26.04's libc;
# the real question is the renderer: ES-DE is documented to want desktop GL 3.3+ or
# Vulkan, and this board offers GL 3.1 compat + GLES 3.1 with no Vulkan ICD.
# So: read its own option list, then run it for a while and capture what the GL
# initialisation says, plus whether the process survives (surviving == a window).
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
SECS=${SECS:-20}
timeout 300 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV "SECS=$SECS sh -s" <<'EOS'
export XDG_RUNTIME_DIR=/run/wayland WAYLAND_DISPLAY=wayland-0
export HOME=/root
echo "  host=$(hostname) weston=$(systemctl is-active weston) stall=$(journalctl -b -k --no-pager 2>/dev/null | grep -cE 'vblank wait timed out|wait_for_vblanks|flip_done timed out')"
A=/root/squashfs-root/AppRun
echo "=== its own options ==="
timeout 25 $A --help 2>&1 | head -40 | sed 's/^/  /'
echo
echo "=== run it for ${SECS}s (no display server tricks, wayland env already set) ==="
(setsid timeout $((SECS+15)) $A > /tmp/esde-run.log 2>&1 &)
i=0
while [ $i -lt $SECS ]; do
  sleep 4; i=$((i+4))
  echo "   t=${i}s alive=$(pgrep -c -f 'es-de' )  weston=$(systemctl is-active weston)"
done
echo
echo "=== what it said ==="
head -40 /tmp/esde-run.log 2>/dev/null | sed 's/^/     /'
echo "  log lines: $(wc -l < /tmp/esde-run.log 2>/dev/null)"
echo "  alive now: $(pgrep -c -f 'es-de')"
echo
echo "=== weston's view: did a client actually map? ==="
journalctl -u weston --no-pager --since "-${SECS}0 seconds" 2>/dev/null | grep -viE "cursor 'dnd" | tail -12 | sed 's/^/     /'
echo "  stall messages now: $(journalctl -b -k --no-pager 2>/dev/null | grep -cE 'vblank wait timed out|wait_for_vblanks|flip_done timed out')"
echo "  free mem: $(awk '/MemAvailable/{print int($2/1024)"MB"}' /proc/meminfo)"
EOS
echo "=== ES-DE run attempt done ==="
