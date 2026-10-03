#!/bin/bash
# k72-es-j1.sh - switch the remaining ES build to a single compile job.
#
# Measured reason: two cc1plus at ~350 MB each on a 972 MB board, so both pages hard
# and the box spends its time on SD swap (si/so up to 6 MB/s, wa up to 43%) while user
# CPU is only ~35% of 4 cores.  One job fits in RAM, so total CPU work drops even
# though parallelism does.
#
# Ordering matters: kill make first (so no new job starts), then the compilers, then
# delete objects written in the last few minutes - a truncated .o left by a killed
# compiler would be newer than its source and make would happily skip it until the
# link fails with a confusing error.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 300 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
before=$(grep -oE '\[ *[0-9]+%\]' /tmp/esrn-build.log 2>/dev/null | tail -1)
echo "  host=$(hostname)  progress before: $before"
pkill -f 'cmake --build' 2>/dev/null; sleep 1
pkill -x gmake 2>/dev/null; pkill -x make 2>/dev/null; sleep 1
pkill -x cc1plus 2>/dev/null; sleep 2
echo "  remaining compiler procs: $(pgrep -c -x cc1plus)"
echo "=== drop objects touched in the last 3 minutes (possible truncation) ==="
find /root/esrn/build -name '*.o' -newermt '-3 minutes' 2>/dev/null | head -6 | sed 's/^/     /'
n=$(find /root/esrn/build -name '*.o' -newermt '-3 minutes' 2>/dev/null | wc -l)
find /root/esrn/build -name '*.o' -newermt '-3 minutes' -delete 2>/dev/null
echo "  removed $n possibly-truncated object(s)"
echo
echo "=== restart with --parallel 1, appending to the same log ==="
echo "----- resuming at $(date +%T) with -j1 -----" >> /tmp/esrn-build.log
(setsid nice -n 5 cmake --build /root/esrn/build --parallel 1 >> /tmp/esrn-build.log 2>&1 &)
sleep 10
echo "  started: $(pgrep -c -x cc1plus) compiler(s), progress now $(grep -oE '\[ *[0-9]+%\]' /tmp/esrn-build.log | tail -1)"
echo "  mem: $(grep MemAvailable /proc/meminfo)  $(grep SwapFree /proc/meminfo)"
echo
echo "  rate check: note this timestamp; k72-es-j1-rate.sh compares progress after 4 min"
date +%T > /tmp/esrn-j1-start
EOS
echo "=== now wait ~4 min and run: bash build/k72-es-j1-rate.sh ==="
