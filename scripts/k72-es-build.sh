#!/bin/bash
# k72-es-build.sh - start the EmulationStation compile detached and bail out
# quickly.  A 4x Cortex-A35 with 972 MB takes far longer than one ssh command
# should hold, so the build runs under setsid and writes /tmp/es-build.log;
# k72-es-status.sh is the poller.
#
# -j2 on purpose: with 1G swap on the SD card, -j4 in a template-heavy ES TU
# swaps hard and gets slower, not faster.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
JOBS=${JOBS:-2}
timeout 120 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV "sh -s" <<EOS
cd /root/es || { echo "  !! /root/es missing - run k72-es-prepare.sh first"; exit 1; }
[ -f build/CMakeCache.txt ] || { echo "  !! not configured yet (build/CMakeCache.txt missing)"; exit 1; }
# the one line that matters: -DGL=ON must have won over the automatic GLES2 probe,
# otherwise we are building the wrong renderer for a board whose desktop GL works
grep -E "^GLSystem|^GLES|^GL:" build/CMakeCache.txt 2>/dev/null | sed 's/^/  cache: /'
grep -E "^CMAKE_BUILD_TYPE|^USE_SYSTEM_PUGIXML|^CEC" build/CMakeCache.txt 2>/dev/null | sed 's/^/  cache: /'
echo "  already running? \$(pgrep -c -f 'make|cc1plus') compiler/make procs"
pgrep -f "cmake --build|make -j" >/dev/null && { echo "  a build is already running, leaving it alone"; exit 0; }
: > /tmp/es-build.log
(setsid nice -n 5 cmake --build build --parallel $JOBS >> /tmp/es-build.log 2>&1 &)
sleep 6
echo "  started (jobs=$JOBS), log /tmp/es-build.log:"
tail -6 /tmp/es-build.log | sed 's/^/     /'
echo "  mem: \$(grep -E 'MemAvailable|^SwapTotal|^SwapFree' /proc/meminfo | tr '\n' ' ')"
EOS
echo "=== build launched; poll with: bash tools/system/diagnostics/k72-es-status.sh ==="
