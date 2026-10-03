#!/bin/bash
# k72-esrn-onbuild.sh - block until the EmulationStation binary exists (or the build
# dies), then run whatever command is passed as arguments.  This exists so a requested
# phase does not have to wait for me to poll: the relay fires the moment it is possible.
#
#   bash k72-esrn-onbuild.sh env PHASE=A bash /mnt/e/ubuntu/build/k72-es-smoke.sh
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
LIMIT=${LIMIT:-420}

[ $# -ge 1 ] || { echo "usage: k72-esrn-onbuild.sh <command...>   (LIMIT=seconds, default 420)"; exit 2; }

timeout $((LIMIT + 90)) sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV "LIMIT=$LIMIT sh -s" <<'EOS'
start=$(date +%s)
while :; do
  bin=$(find /root/esrn/build -maxdepth 4 -type f -name emulationstation 2>/dev/null | head -1)
  jobs=$(pgrep -c -f 'cmake --build|cc1plus|c1plus' 2>/dev/null); jobs=${jobs%%$'\n'*}
  now=$(date +%s)
  [ -n "$bin" ] && { echo "=== binary ready: $bin (after $((now-start))s) ==="; exit 0; }
  if [ -z "$jobs" ] || [ "$jobs" = 0 ]; then
    echo "=== build processes gone and no binary after $((now-start))s ==="
    grep -E 'error:|Error [0-9]' /tmp/esrn-build.log 2>/dev/null | head -6 | sed 's/^/     /'
    tail -3 /tmp/esrn-build.log 2>/dev/null | sed 's/^/     /'
    exit 1
  fi
  [ $((now - start)) -ge "$LIMIT" ] && { echo "=== still building after $LIMIT s (progress $(grep -oE '\[ *[0-9]+%\]' /tmp/esrn-build.log 2>/dev/null | tail -1)) ==="; exit 2; }
  sleep 15
done
EOS
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "=== relay gave up (rc=$rc; 2 = still building, re-arm me) ==="
  exit "$rc"
fi
echo "=== running: $* ==="
"$@"
echo "=== relayed command rc=$? ==="
