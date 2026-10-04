#!/bin/bash
# notify-wait.sh - block until the board has finished "build + phase A", then print
# the verdict in the same call.  It reports three distinct outcomes, because conflating
# them is exactly what caused wrong claims earlier in this project:
#   0  the smoke transcript exists and the .done marker was touched  -> print the transcript
#   1  the watcher is gone with no transcript (build/link died)      -> print its log + build errors
#   2  still working when the budget ran out                         -> print progress, caller re-arms
# The budget is under ten minutes on purpose so it fits a single tool call; re-arming is
# one cheap call, and a re-arm that prints fresh progress is more honest than one long
# silent sleep.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
LIMIT=${LIMIT:-520}
PHASE=${PHASE:-A}
TREE=${TREE:-es}

timeout $((LIMIT + 60)) sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV \
  "LIMIT=$LIMIT PHASE=$PHASE TREE=$TREE sh -s" <<'EOS'
start=$(date +%s)
while :; do
  now=$(date +%s)
  if [ -f "/tmp/es-smoke-$PHASE.done" ]; then
    echo "=== phase $PHASE finished at $(date '+%T'); transcript /tmp/es-smoke-$PHASE.txt ==="
    sed 's/^/  /' "/tmp/es-smoke-$PHASE.txt" 2>/dev/null
    echo "=== es-a.log (ES's own stdout/stderr, first 30 lines) ==="
    head -30 /tmp/es-a.log 2>/dev/null | sed 's/^/  /'
    echo "=== kernel stalls now: $(journalctl -b -k --no-pager 2>/dev/null | grep -cE 'vblank wait timed out|wait_for_vblanks|flip_done timed out') ==="
    exit 0
  fi
  if ! pgrep -f 'es-watch.sh' > /dev/null; then
    echo "=== watcher is gone and there is no transcript: this is a real failure ==="
    tail -10 "/tmp/es-watch-$TREE.log" 2>/dev/null | sed 's/^/     /'
    echo "  --- build log tail ---"
    tail -6 "/tmp/es-$TREE-build.log" 2>/dev/null | sed 's/^/     /'
    echo "  --- errors ---"
    grep -E 'error:|Error [0-9]|Killed|oom' "/tmp/es-$TREE-build.log" 2>/dev/null | tail -6 | sed 's/^/     /'
    echo "  --- oom kills in dmesg: $(dmesg 2>/dev/null | grep -ci 'oom-kill') ---"
    exit 1
  fi
  if [ $((now - start)) -ge "$LIMIT" ]; then
    echo "=== still working after ${LIMIT}s ==="
    echo "  progress: $(grep -oE '\[ *[0-9]+%\]' "/tmp/es-$TREE-build.log" 2>/dev/null | tail -1)   started this run: $(grep -c 'Building CXX object' "/tmp/es-$TREE-build.log" 2>/dev/null)   errors: $(grep -c 'error:' "/tmp/es-$TREE-build.log" 2>/dev/null)"
    echo "  current : $(grep -E 'Building CXX|Linking' "/tmp/es-$TREE-build.log" 2>/dev/null | tail -1 | cut -c1-100)"
    echo "  binary  : $([ -x "/root/$TREE/build/es-app/emulationstation" ] && echo 'linked, smoke in progress' || echo 'not linked yet')"
    echo "  mem     : $(grep -E 'MemAvailable|^SwapFree' /proc/meminfo | tr '\n' ' ')  io_psi=$(cut -d= -f2 /proc/pressure/io | head -1 | cut -d' ' -f1)"
    echo "  uptime  : $(cut -d' ' -f1 /proc/uptime)s   (same boot = no surprise reboot)"
    exit 2
  fi
  sleep 20
done
EOS
rc=$?
echo "=== notify-wait rc=$rc (0 done, 1 failed, 2 re-arm me) ==="
exit "$rc"
