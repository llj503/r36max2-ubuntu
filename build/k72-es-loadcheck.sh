#!/bin/bash
# k72-es-loadcheck.sh - is the ES build actually progressing, or thrashing?
# Shows swap in/out rate, which TUs are running and for how long, and per-CPU
# pressure, so the decision to drop -j2 to -j1 is based on numbers and not on my
# impatience.  (Fewer parallel compiles can be FASTER when the box is swapping.)
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 120 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
echo "  host=$(hostname)  progress=$(grep -oE '\[ *[0-9]+%\]' /tmp/esrn-build.log 2>/dev/null | tail -1)  errors=$(grep -c 'error:' /tmp/esrn-build.log 2>/dev/null)"
echo "  psi memory: $(cat /proc/pressure/memory 2>/dev/null | head -1)"
echo "  psi io    : $(cat /proc/pressure/io 2>/dev/null | head -1)"
echo "=== 6 seconds of vmstat (si/so are the numbers that matter) ==="
vmstat 2 6 2>/dev/null | sed 's/^/  /'
echo "=== what is compiling right now ==="
ps -o pid=,etime=,rss=,%cpu=,comm= -C cc1plus,ld 2>/dev/null | head -6 | sed 's/^/  /'
echo "=== last 40 lines of build log, newest progress ==="
tail -4 /tmp/esrn-build.log 2>/dev/null | cut -c1-110 | sed 's/^/  /'
echo "=== swap layout ==="
free -m | awk '/Mem|Swap/{print "  " $0}'
EOS
echo "=== load check done ==="
