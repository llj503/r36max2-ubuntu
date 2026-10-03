#!/bin/bash
# k72-vop-drmdebug.sh - make the DRM core narrate the failure using its own runtime
# debug switch, since this kernel has no ftrace/kprobes (CONFIG_FTRACE/KPROBES unset).
#
# Categories (enum drm_debug_category, bit = 1<<n):
#   CORE 0x01  DRIVER 0x02  KMS 0x04  PRIME 0x08  ATOMIC 0x10  VBL 0x20  STATE 0x40
# -> mask 0x37 covers the vblank + atomic + modesetting story without the per-object
#    STATE flood.
#
# The reproduction is the deterministic one (plain SDL2 kmsdrm modeset, ~60 s to hang),
# and this time the probe is started under stdbuf so a SIGTERM cannot swallow its
# output - that exact loss is why one earlier run "proved" nothing happened.
#
# Run with weston stopped so the probe is the only DRM client.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
MASK=${MASK:-0x37}
timeout 420 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV "MASK=$MASK sh -s" <<'EOS'
irq() { awk '/vop/{for(i=2;i<=NF;i++) if($i ~ /^[0-9]+$/) {print $i; exit}}' /proc/interrupts; }
echo "  host=$(hostname) uptime=$(cut -d. -f1 /proc/uptime)s"
echo "  weston=$(systemctl is-active weston)  stall=$(journalctl -b -k --no-pager 2>/dev/null | grep -cE 'vblank wait timed out|wait_for_vblanks|flip_done timed out')"
echo "  vblankoffdelay=$(cat /sys/module/drm/parameters/vblankoffdelay)  drm.debug=$(cat /sys/module/drm/parameters/debug)"
echo
echo "=== stop weston so the probe is the only client ==="
systemctl stop weston 2>/dev/null
i=0; while [ $i -lt 25 ] && pgrep -x weston >/dev/null; do sleep 3; i=$((i+3)); done
echo "  weston=$(systemctl is-active weston) procs=$(pgrep -cx weston) vt=$(fgconsole 2>/dev/null)"
a=$(irq); sleep 2; b=$(irq)
echo "  vop irq with only the console up: $a -> $b (delta $((b-a)))"
echo
echo "=== enable DRM debug mask=$MASK ==="
echo $MASK > /sys/module/drm/parameters/debug
echo "  now drm.debug=$(cat /sys/module/drm/parameters/debug)"
base=$(journalctl -b -k --no-pager 2>/dev/null | wc -l)
c=$(irq)
echo
echo "=== reproduce: SDL kmsdrm modeset (unbuffered this time) ==="
timeout 150 systemd-run --unit=vdbg --wait --collect --no-ask-password \
  -p Type=oneshot -p TTYPath=/dev/tty1 -p StandardInput=tty -p TTYVTDisallocate=no \
  -p Environment=HOME=/root -p Environment=XDG_VTNR=1 -p TimeoutStartSec=55 \
  /bin/sh -c "stdbuf -oL -eL /usr/local/bin/r36-sdlprobe kmsdrm > /tmp/vdbg.log 2>&1; echo rc=\$? >> /tmp/vdbg.log" >/dev/null 2>&1
echo "  systemd-run rc=$?  (0 = probe exited by itself, non-0 = it got killed = hung)"
echo "  vop irq across the attempt: $c -> $(irq)"
echo "  --- probe's own log ---"
sed 's/^/     /' /tmp/vdbg.log 2>/dev/null | head -20
echo
echo "=== what the DRM core said during the attempt (last 45 lines of new kernel output) ==="
journalctl -b -k --no-pager --since '-3 minutes' 2>/dev/null | grep -E "vblank|vop|atomic|drm|crtc" | tail -45 | sed 's/^/  /'
echo
echo "=== the vblank-specific lines alone (this is the answer we came for) ==="
journalctl -b -k --no-pager --since '-3 minutes' 2>/dev/null | grep -iE "vblank" | tail -25 | sed 's/^/  /'
echo "  count of 'vblank enable' vs 'vblank disable' in the window:"
journalctl -b -k --no-pager --since '-3 minutes' 2>/dev/null | grep -ic "vblank enable" | sed 's/^/     enable:  /'
journalctl -b -k --no-pager --since '-3 minutes' 2>/dev/null | grep -ic "vblank disable" | sed 's/^/     disable: /'
echo
echo "=== turn the noise off again ==="
echo 0 > /sys/module/drm/parameters/debug
echo "  drm.debug=$(cat /sys/module/drm/parameters/debug)"
systemctl start weston; sleep 5
echo "  weston=$(systemctl is-active weston)  stall now=$(journalctl -b -k --no-pager 2>/dev/null | grep -cE 'vblank wait timed out|wait_for_vblanks|flip_done timed out')"
EOS
echo "=== drm.debug experiment done ==="
