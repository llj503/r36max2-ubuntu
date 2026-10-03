#!/bin/bash
# k72-gpucrash-triage.sh - the user reports the panel is showing a "cmd queue
# crashed" style message again: that string comes from the panfrost driver, so the
# GPU hung while weston was compositing.  Establish: when, what was running,
# whether weston survived, whether the GPU recovered, and what 6.12 did differently.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 120 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
echo "=== now / uptime ==="
date '+  %H:%M:%S'; cut -d' ' -f1 /proc/uptime | sed 's/^/  uptime s: /'

echo
echo "=== every GPU / DRM message since boot, with timestamps ==="
journalctl -b --no-pager -k | grep -iE "panfrost|gpu|ff900000|drm|mmu|reset|seqnode|cmd queue" |
  tail -40 | sed 's/^/  /'

echo
echo "=== the crash window in wall-clock terms ==="
journalctl -b --no-pager | grep -iE "cmd queue|gpu reset|panfrost" | head -5 | sed 's/^/  first: /'
journalctl -b --no-pager | grep -iE "cmd queue|gpu reset|panfrost" | tail -3 | sed 's/^/  last : /'

echo
echo "=== is weston alive, and what happened to it? ==="
echo "  weston: $(systemctl is-active weston)  pid $(systemctl show -p MainPID --value weston)  since $(systemctl show -p ExecMainStartTimestamp --value weston)"
echo "  keymapper: $(systemctl is-active r36-keymapper)  pid $(systemctl show -p MainPID --value r36-keymapper)"
echo "  weston restarts: $(systemctl show -p NRestarts --value weston)"
journalctl -u weston --no-pager -n 25 | sed 's/^/    /'

echo
echo "=== what clients are alive right now ==="
ps -o pid=,rss=,etime=,comm= -C weston-simple-egl,weston-flower,foot,wofi,weston-keyboard,weston-desktop-shell,weston 2>/dev/null | sed 's/^/  /'

echo
echo "=== GPU state ==="
for f in /sys/class/devfreq/*gpu/cur_freq /sys/class/devfreq/*gpu/available_frequencies /sys/class/devfreq/*gpu/governor; do
  [ -e "$f" ] && echo "  $(basename $f): $(cat $f)"
done
echo "  drm clients: $(ls /sys/class/drm/card0/device/ 2>/dev/null | grep -c gem)"
echo "  error counters: $(for s in /sys/class/devfreq/*gpu/stat/*/; do echo -n "$(basename $s)="; cat $s; done 2>/dev/null | tr -d '\n')"
echo

echo "=== did the console come back (weston dead) ? ==="
echo "  getty@tty1: $(systemctl is-active getty@tty1)   active vt: $(fgconsole 2>/dev/null)"
echo "  fbcon blank: $(cat /sys/class/graphics/fb0/blank 2>/dev/null)"
echo "  panel: $(cat /sys/class/drm/card0-DSI-1/status 2>/dev/null) $(cat /sys/class/drm/card0-DSI-1/modes 2>/dev/null | head -1)"

echo
echo "=== anything in the panfrost drop list that looks relevant? ==="
ls /mnt/e/ubuntu/build/rocknix/patches 2>/dev/null | head -5 | sed 's/^/  (see repo) /'
EOS

echo
echo "=== the panfrost patches we dropped for 7.2.8 ==="
ls /mnt/e/ubuntu/build/rocknix/patches/panfrost* 2>/dev/null | sed 's/^/  /'
ls /mnt/e/ubuntu/build/rocknix/patches 2>/dev/null | grep -iE "panfrost|mali|gpu" | sed 's/^/  /'
echo "=== triage done ==="
