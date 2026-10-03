#!/bin/bash
# k72-vbo-check.sh - the vblankoffdelay experiment's output got cut off, so read the
# state the device is actually in: did the SDL unit even run, what did it print, is
# the pipeline still clean, and is the panel still alive.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 120 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
irq() { awk '/vop/{for(i=2;i<=NF;i++) if($i ~ /^[0-9]+$/) {print $i; exit}}' /proc/interrupts; }
echo "  host=$(hostname) uptime=$(cut -d. -f1 /proc/uptime)s"
echo "  vblankoffdelay now = $(cat /sys/module/drm/parameters/vblankoffdelay)"
echo "  weston=$(systemctl is-active weston) keymapper=$(systemctl is-active r36-keymapper) fgvt=$(fgconsole 2>/dev/null)"
echo "  stall since boot = $(journalctl -b -k --no-pager 2>/dev/null | grep -cE 'vblank wait timed out|wait_for_vblanks|flip_done timed out')"
echo "  vop irq sampled twice 3s apart:"
a=$(irq); sleep 3; b=$(irq); echo "     $a -> $b (delta $((b-a)))"
echo
echo "=== the vbo unit: did it run at all? ==="
ls -l /tmp/vbo.log 2>/dev/null | sed 's/^/  /'
echo "  content: [$(cat /tmp/vbo.log 2>/dev/null | tr '\n' '|' | head -c 400)]"
journalctl -b --no-pager -u vbo.service 2>/dev/null | tail -12 | sed 's/^/     /'
echo
echo "=== anything in the kernel log about our probe or the vop ==="
journalctl -b -k --no-pager 2>/dev/null | grep -iE "vop|drm|kms" | tail -12 | sed 's/^/     /'
echo
echo "=== egl/weston clients present? ==="
echo "  procs: $(pgrep -a -f 'weston-simple|emulationstation|r36-sdlprobe' | head -4 | tr '\n' ' ')"
echo "  weston last 8:"
journalctl -u weston --no-pager -n 8 2>/dev/null | sed 's/^/     /'
EOS
echo "=== check done ==="
