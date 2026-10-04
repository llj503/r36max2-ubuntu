#!/bin/bash
# k72-es-rate.sh - comparable progress: how many translation units per minute the
# build is finishing since the -j1 restart, how many are left, and what the current
# one costs. The cmake "[ N%]" number is not comparable across a make restart, so
# this counts log lines instead.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 150 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
L=/tmp/esrn-build.log
marker=$(grep -n "resuming at" "$L" 2>/dev/null | tail -1 | cut -d: -f1)
[ -n "$marker" ] || marker=1
since=$(tail -n +$marker "$L" 2>/dev/null | grep -c "Building CXX object")
sincec=$(tail -n +$marker "$L" 2>/dev/null | grep -c "Building C object")
el=$(( $(date +%s) - $(stat -c %Y /tmp/esrn-j1-start 2>/dev/null || date +%s) ))
[ $el -gt 0 ] || el=1
total=$(find /root/esrn/build -name '*.build' 2>/dev/null | wc -l)
objs=$(find /root/esrn/build -name '*.o' 2>/dev/null | wc -l)
todo=$(find /root/esrn/es-app /root/esrn/es-core -name '*.cpp' 2>/dev/null | wc -l)
echo "  host=$(hostname)  uptime=$(cut -d. -f1 /proc/uptime)s"
echo "  since the -j1 restart: ${el}s, ${since} CXX + ${sincec} C objects compiled  -> $(awk -v a=$since -v b=$el 'BEGIN{printf "%.2f", a*60/b}') files/min"
echo "  objects on disk: $objs   (cpp sources under es-app+es-core: $todo)"
# NOTE: no "remaining TUs" arithmetic here on purpose - $objs counts every target
# (externals, es-core, tests) while $todo counts only two directories, so the two
# are not comparable and an arithmetic estimate on them prints nonsense (a previous
# version happily reported "-65 TUs => ~-65 min").  Trust files/min + wa + the log.
echo "  current compile: $(ps -o etime=,rss=,comm= -C cc1plus 2>/dev/null | head -2 | tr '\n' ' ')"
tail -2 "$L" | cut -c1-100 | sed 's/^/     /'
echo "  mem: $(grep MemAvailable /proc/meminfo)  $(grep SwapFree /proc/meminfo)"
echo "  psi mem: $(cat /proc/pressure/memory 2>/dev/null | head -1)"
echo "  user CPU over 6s: $(vmstat 3 3 2>/dev/null | tail -1 | awk '{print "us="$16"%"  " wa="$18"%  idle="$19"%"}')"
EOS
echo "=== rate measured ==="
