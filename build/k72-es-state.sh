#!/bin/bash
# k72-es-state.sh - what is actually running and who owns the display, right now.
#
# Triggered by a concrete worry: after phase A, two processes still matched the ES path
# even after pkill, and `systemctl is-active weston` came back "inactive" although the
# smoke script had started it and reported it active at the end.  An ES process that keeps
# DRM master with no compositor (or a weston that died) is exactly how this board ends up
# with a black panel that only a reboot fixes - so this is read-only forensics, first.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 120 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
echo "  host=$(hostname)  uptime=$(cut -d' ' -f1 /proc/uptime)s  boot_id=$(cat /proc/sys/kernel/random/boot_id)"
echo "=== every process whose name or cmdline mentions emulationstation ==="
ps -eo pid,ppid,stat,etimes,rss,comm,args | grep -i '[e]mulationstation' | cut -c1-150 | sed 's/^/  /'
echo "  (stat column: D = uninterruptible, usually stuck in the kernel/driver; Z = zombie)"
echo "=== weston ==="
echo "  unit: $(systemctl is-active weston)   procs: $(pgrep -cx weston 2>/dev/null || echo 0)"
ps -eo pid,stat,etimes,args | grep '[w]eston' | cut -c1-120 | sed 's/^/     /'
echo "  --- journal since 4 minutes ago ---"
journalctl -u weston --no-pager --since '-4 minutes' 2>/dev/null | tail -18 | sed 's/^/     /'
echo "=== who holds the DRM card ==="
for p in $(ls /proc | grep -E '^[0-9]+$'); do
  if ls -l /proc/$p/fd 2>/dev/null | grep -q '/dev/dri/card'; then
    echo "  pid $p ($(cat /proc/$p/comm 2>/dev/null)) holds a /dev/dri/card fd: $(ls -l /proc/$p/fd 2>/dev/null | grep -o '/dev/dri/card[0-9]*' | tr '\n' ' ')"
  fi
done
echo "  master by kernel: $(grep -i 'drm' /sys/class/drm/card0/device/master 2>/dev/null || echo '(no sysfs master file)')"
echo "=== wayland sockets and clients ==="
ls -l /run/wayland* 2>/dev/null | sed 's/^/  /'
ls -l /run/user/0/ 2>/dev/null | head -6 | sed 's/^/  /'
echo "=== ES's own last words ==="
echo "  --- /tmp/es-a.log (full) ---"
cat /tmp/es-a.log 2>/dev/null | sed 's/^/     /'
echo "  --- ~/.emulationstation/es_log.txt (full) ---"
cat /root/.emulationstation/es_log.txt 2>/dev/null | sed 's/^/     /'
echo "=== kernel side: any vblank/flip trouble in this boot ==="
echo "  stalls: $(journalctl -b -k --no-pager 2>/dev/null | grep -cE 'vblank wait timed out|wait_for_vblanks|flip_done timed out')"
journalctl -b -k --no-pager 2>/dev/null | grep -iE 'vop|drm|panfrost' | tail -6 | sed 's/^/     /'
echo "=== screen state as the kernel sees it ==="
cat /sys/class/drm/card0-DSI-1/status 2>/dev/null | sed 's/^/  DSI-1: /'
for c in /sys/class/drm/card0-*/enabled; do [ -f "$c" ] && echo "  $(basename $(dirname $c)): $(cat $c)"; done
EOS
