#!/bin/bash
# k72-es-status.sh - how far along is the EmulationStation build, and did anything
# fail?  Reads the detached build log; safe to run repeatedly.
# Exit codes: 0 still building, 1 errors, 2 finished with a binary, 3 nothing running
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 90 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
cd /root/es 2>/dev/null || { echo "  no /root/es"; exit 3; }
# grep -c / pgrep -c already PRINT 0 when nothing matched (and exit non-zero), so
# `|| echo 0` appends a SECOND line -> $errs becomes "0\n0" -> the != 0 test below
# is true and the poller screams "errors" about a perfectly clean build.
alive=$(pgrep -c -f 'cmake --build|cc1plus|make' 2>/dev/null); alive=${alive%%$'\n'*}
prog=$(grep -oE '\[ *[0-9]+%\]' /tmp/es-build.log 2>/dev/null | tail -1)
errs=$(grep -cE 'error:|Error [0-9]|ninja: build stopped|undefined reference' /tmp/es-build.log 2>/dev/null); errs=${errs%%$'\n'*}
bin=$(find build -maxdepth 2 -type f \( -name emulationstation -o -name 'emulationstation-standalone' -o -name ES - \) 2>/dev/null | tr '\n' ' ')
[ -n "$alive" ] || alive=0
[ -n "$errs" ] || errs=0
bin=$(find build -maxdepth 2 -type f \( -name emulationstation -o -name 'emulationstation-standalone' -o -name ES - \) 2>/dev/null | tr '\n' ' ')
echo "  host=$(hostname)  build procs=$alive  progress=$prog  error lines=$errs"
echo "  binaries: ${bin:-none yet}"
echo "  ram=$(awk '/MemAvailable/{print int($2/1024)"MB"}' /proc/meminfo) swap=$(free -m | awk '/^Swap/{print $3"MB used"}') load=$(cut -d" " -f1-3 /proc/loadavg)"
echo "  log tail:"
tail -12 /tmp/es-build.log 2>/dev/null | sed 's/^/     /'
if [ "$errs" != 0 ]; then
  echo "  --- first errors ---"
  grep -nE 'error:|undefined reference|fatal error' /tmp/es-build.log 2>/dev/null | head -12 | sed 's/^/     /'
fi
if [ -n "$bin" ]; then echo "  === ES BINARY BUILT: $bin ==="; exit 2; fi
[ "$errs" != 0 ] && exit 1
[ "$alive" = 0 ] && { echo "  !! nothing running and no binary - the build stopped"; exit 3; }
exit 0
EOS
rc=$?
echo "=== status rc=$rc (0 building, 1 errors, 2 built, 3 stopped/absent) ==="
exit $rc
