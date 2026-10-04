#!/bin/bash
# k72-es-j1-rate.sh - did dropping to --parallel 1 actually help?  Measures progress
# per minute since k72-es-j1.sh restarted the build, plus swap traffic, and states the
# verdict instead of letting me eyeball a percentage and guess.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 150 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
start=$(cat /tmp/esrn-j1-start 2>/dev/null || echo "")
now=$(date +%s)
[ -n "$start" ] && el=$((now - $(date -d "$start" +%s 2>/dev/null || echo $now))) || el=0
p=$(grep -oE '\[ *[0-9]+%\]' /tmp/esrn-build.log 2>/dev/null | tail -1)
echo "  host=$(hostname)  progress=$p   elapsed since -j1 restart: ${el}s"
echo "  mem: $(grep MemAvailable /proc/meminfo)  $(grep SwapFree /proc/meminfo)"
echo "  psi: $(cat /proc/pressure/memory 2>/dev/null | head -1)   io: $(cat /proc/pressure/io 2>/dev/null | head -1)"
echo "  compilers: $(ps -o etime=,rss=,comm= -C cc1plus 2>/dev/null | tr '\n' ' ')"
echo "  last lines:"
tail -3 /tmp/esrn-build.log 2>/dev/null | cut -c1-100 | sed 's/^/     /'
echo "  swap in/out over 6s:"
vmstat 3 3 2>/dev/null | tail -3 | awk '{printf "     si=%s so=%s wa=%s%% idle=%s%%\n", $7, $8, $(NF-2), $10}'
bin=$(find /root/esrn/build -maxdepth 4 -type f -name emulationstation 2>/dev/null | head -1)
[ -n "$bin" ] && { echo "  === BINARY READY: $bin ==="; exit 2; }
exit 0
EOS
rc=$?
[ $rc = 2 ] && echo "=== binary is built - run: PHASE=A bash tools/emulationstation/verify/k72-es-smoke.sh ==="
exit $rc
