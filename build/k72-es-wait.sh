#!/bin/bash
# k72-es-wait.sh - block server-side until the EmulationStation build produces the
# binary or stops, then print one summary.  Waiting should be one round trip, not a
# polling loop from this side.
#
# The heredoc is fully quoted and the limit is passed as an environment variable in
# the *remote command* (`LIM=n sh -s`), because the nested `sh -c "..."` version of
# this script turned into an quoting maze that dash then mis-parsed.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
LIMIT=${LIMIT:-500}
timeout $((LIMIT + 90)) sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV "LIM=$LIMIT sh -s" <<'EOS'
start=$(date +%s)
status=2
while :; do
  bin=$(find /root/es/build -maxdepth 2 -type f -name emulationstation 2>/dev/null | head -1)
  jobs=$(pgrep -c -f 'cmake --build|cc1plus' 2>/dev/null); jobs=${jobs%%$'\n'*}
  now=$(date +%s)
  if [ -n "$bin" ]; then status=0; echo "=== BINARY: $bin ==="; break; fi
  if [ -z "$jobs" ] || [ "$jobs" = 0 ]; then status=1; echo "=== build processes gone, no binary ==="; break; fi
  if [ $((now - start)) -ge "$LIM" ]; then status=2; echo "=== still building after ${LIM}s ==="; break; fi
  sleep 20
done
echo "  elapsed: $((now - start))s"
echo "  progress: $(grep -oE '\[ *[0-9]+%\]' /tmp/es-build.log 2>/dev/null | tail -1)"
echo "  ram=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)MB  swap_used=$(free -m | awk '/^Swap/{print $3}')MB  load=$(cut -d' ' -f1 /proc/loadavg)"
echo "  real errors: $(grep -c 'error:' /tmp/es-build.log 2>/dev/null)"
grep -E 'error:|undefined reference|No such file or directory' /tmp/es-build.log 2>/dev/null | head -10 | sed 's/^/     /'
echo "  last lines:"
tail -4 /tmp/es-build.log 2>/dev/null | sed 's/^/     /'
exit $status
EOS
rc=$?
echo "=== wait rc=$rc (0=binary built, 1=stopped without binary, 2=still building) ==="
exit $rc
