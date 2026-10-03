#!/bin/bash
# k72-es-free-ram.sh - the ES build is swapping on an SD card (1% per 7 min). Nothing
# graphical is needed while it compiles - smoke phase A starts weston itself - so stop
# the compositor, its helpers and the on-screen keyboard to hand their RSS back to the
# compilers, then re-measure whether progress per minute improves.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 200 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
echo "  host=$(hostname)  progress=$(grep -oE '\[ *[0-9]+%\]' /tmp/esrn-build.log 2>/dev/null | tail -1)"
echo "=== memory holders before ==="
ps -eo rss=,comm= --sort=-rss 2>/dev/null | head -10 | awk '{printf "  %6.0f MB  %s\n", $1/1024, $2}'
for u in r36-keymapper weston; do
  systemctl is-active $u >/dev/null 2>&1 && { echo "  stopping $u"; systemctl stop $u; }
done
pkill -f 'r36-osk' 2>/dev/null; pkill -x wofi 2>/dev/null; pkill -x foot 2>/dev/null
systemctl stop getty@tty1.service 2>/dev/null
sleep 3
echo "=== after ==="
grep -E 'MemAvailable|^SwapTotal|^SwapFree' /proc/meminfo | sed 's/^/  /'
echo "  psi memory: $(cat /proc/pressure/memory 2>/dev/null | head -1)"
echo "  compilers now: $(ps -o etime=,rss=,comm= -C cc1plus 2>/dev/null | tr '\n' ' ')"
echo "  (re-enable later: systemctl start weston  -> pulls r36-keymapper with it)"
EOS
echo "=== ram freed for the build ==="
