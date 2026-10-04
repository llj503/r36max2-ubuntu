#!/bin/bash
# k72-esrn-autorun.sh - put the smoke test ON the board and let the board decide when to
# run it, so no host-side relay has to be re-armed every few minutes.
#
#   bash scripts/k72-esrn-autorun.sh arm      # push scripts + start the detached watcher (phase A)
#   bash scripts/k72-esrn-autorun.sh status   # watcher log, smoke output, done marker
#   bash scripts/k72-esrn-autorun.sh read     # full phase-A transcript
#   bash scripts/k72-esrn-autorun.sh off      # kill the watcher (does not touch the build)
#
# Watcher rule: exit as soon as the build is dead AND no binary exists (that used to be
# reported as "still building" by a plain timeout loop, which hid real failures).
#
#   TREE=es   bash scripts/k72-esrn-autorun.sh arm     # watch the batocera build
#   TREE=esrn bash scripts/k72-esrn-autorun.sh arm     # watch the ROCKNIX build
#   TREE=es   bash scripts/k72-esrn-autorun.sh status  # watcher + build + pressure in one view
#   TREE=es   bash scripts/k72-esrn-autorun.sh read    # full phase-A transcript
#   PHASE=B TREE=es bash scripts/k72-esrn-autorun.sh arm   # ask for the deeper phase
set -uo pipefail
REPO=${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
PW=ubuntu
DEV=${DEV:-192.168.31.209}
# TREE=es -> batocera's emulationstation (desktop GL); TREE=esrn -> ROCKNIX's
# emulationstation-next (GLES3).  Both link to <tree>/build/es-app/emulationstation.
TREE=${TREE:-es}
DIR=/root/$TREE
BIN=${BIN:-$DIR/build/es-app/emulationstation}
ESBIN=${ESBIN:-$BIN}
PHASE=${PHASE:-A}
MAXS=${MAXS:-10800}
LOG=${LOG:-/tmp/es-$TREE-build.log}
cmd=${1:-status}
WATCHLOG=/tmp/es-watch-$TREE.log

case "$cmd" in
run)
  # Run a phase NOW instead of waiting for the watcher, and resolve the artifact from the
  # tree rather than trusting the path copied from the other fork.
  timeout 480 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV \
    "DIR=$DIR PHASE=$PHASE WAIT=${WAIT:-25} TREE=$TREE sh -s" <<'EOS'
[ -f /root/es-smoke-device.sh ] || { echo "  !! /root/es-smoke-device.sh missing - run: ... arm first"; exit 1; }
BIN=$(find "$DIR" -maxdepth 3 -type f -name emulationstation -perm -u+x 2>/dev/null | head -1)
if [ -z "$BIN" ]; then
  echo "  !! no executable named 'emulationstation' anywhere under $DIR"
  echo "     build tail: $(tail -2 /tmp/es-$TREE-build.log 2>/dev/null | tr '\n' ' ')"
  exit 1
fi
echo "  artifact: $BIN  ($(stat -c %s "$BIN") bytes, linked $(stat -c %y "$BIN" | cut -c1-19))"
echo "  phase=$PHASE wait=${WAIT}s"
rm -f "/tmp/es-smoke-$PHASE.done"
ESBIN="$BIN" PHASE="$PHASE" WAIT="$WAIT" sh /root/es-smoke-device.sh 2>&1 | sed 's/^/  /'
echo "  (transcript also in /tmp/es-smoke-$PHASE.txt)"
EOS
  ;;
arm)
  timeout 60 sshpass -p $PW scp -o ConnectTimeout=25 $REPO/tools/emulationstation/verify/es-smoke-device.sh root@$DEV:/root/es-smoke-device.sh >/dev/null 2>&1 \
    || { echo "!! push of es-smoke-device.sh failed"; exit 1; }
  echo "  pushed /root/es-smoke-device.sh"
  timeout 60 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'cat > /root/es-watch.sh' <<'EOW'
#!/bin/sh
# es-watch.sh - wait for an EmulationStation link to finish, then run the smoke phase.
# Everything is env-driven so the same watcher serves both trees:
#   BIN= BUILDDIR= BUILDLOG= ESBIN= MAXS= sh /root/es-watch.sh A
set -u
PHASE=${1:-A}
BIN=${BIN:-/root/esrn/build/es-app/emulationstation}
BUILDDIR=${BUILDDIR:-/root/esrn}
BUILDLOG=${BUILDLOG:-/tmp/esrn-build.log}
ESBIN=${ESBIN:-$BIN}
MAXS=${MAXS:-10800}
start=$(date +%s)
echo "watching for $BIN (phase $PHASE, esbin=$ESBIN, max ${MAXS}s) - started $(date '+%F %T')"
while :; do
  if [ -x "$BIN" ]; then
    echo "=== binary appeared after $(( $(date +%s) - start ))s -> running phase $PHASE ==="
    break
  fi
  # An assumed artifact path is NOT a failure signal.  The batocera tree links to
  # /root/es/emulationstation (CMAKE_RUNTIME_OUTPUT_DIRECTORY at the repo root), not to
  # build/es-app/emulationstation like the esrn tree, and this watcher called a finished
  # build "a real failure" for exactly that reason.  Ask the build log as well, and look
  # for the file wherever it actually is.
  if grep -q 'Built target emulationstation' "$BUILDLOG" 2>/dev/null; then
    found=$(find "$BUILDDIR" -maxdepth 3 -type f -name emulationstation -perm -u+x 2>/dev/null | head -1)
    if [ -n "$found" ]; then
      echo "=== build log says Built target emulationstation; artifact is $found ($(stat -c %s "$found") bytes) ==="
      BIN="$found"
      break
    fi
  fi
  jobs=$(pgrep -c -f 'cmake --build' 2>/dev/null); jobs=${jobs:-0}
  cc=$(pgrep -cx cc1plus 2>/dev/null); cc=${cc:-0}
  ld=$(pgrep -cx ld 2>/dev/null); ld=${ld:-0}
  now=$(date +%s)
  if [ "$jobs" = 0 ] && [ "$cc" = 0 ] && [ "$ld" = 0 ]; then
    echo "=== build processes gone, no binary found under $BUILDDIR and no 'Built target' line (after $((now-start))s) - real failure ==="
    grep -E 'error:|Error [0-9]' "$BUILDLOG" 2>/dev/null | tail -6 | sed 's/^/     /'
    tail -4 "$BUILDLOG" 2>/dev/null | sed 's/^/     /'
    exit 1
  fi
  if [ $((now - start)) -ge "$MAXS" ]; then
    echo "=== watcher gave up after ${MAXS}s; progress $(grep -oE '\[ *[0-9]+%\]' "$BUILDLOG" 2>/dev/null | tail -1) ==="
    exit 2
  fi
  sleep 20
done
# ld writes the executable at the end; give it a moment so -x cannot see a partial file
sleep 5
BINAGE=$(( $(date +%s) - $(stat -c %Y "$BIN") ))
echo "  binary is $BINAGE s old, $(stat -c %s "$BIN") bytes - built at $(stat -c %y "$BIN" | cut -c1-19)"
ESBIN="$ESBIN" sh /root/es-smoke-device.sh > "/tmp/es-smoke-$PHASE.txt" 2>&1
echo "smoke rc=$?" >> "/tmp/es-smoke-$PHASE.txt"
touch "/tmp/es-smoke-$PHASE.done"
echo "=== phase $PHASE finished, transcript in /tmp/es-smoke-$PHASE.txt ==="
EOW
  timeout 90 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV \
    "BIN=$BIN ESBIN=$ESBIN BUILDDIR=$DIR BUILDLOG=$LOG WATCHLOG=$WATCHLOG PHASE=$PHASE MAXS=$MAXS sh -s" <<'EOS'
LOG=${BUILDLOG:-/tmp/es-$TREE-build.log}
echo "  syntax of /root/es-watch.sh: $(sh -n /root/es-watch.sh 2>&1 && echo OK)"
echo "  syntax of /root/es-smoke-device.sh: $(sh -n /root/es-smoke-device.sh 2>&1 && echo OK)"
if [ -x "$BIN" ]; then
  echo "  binary is ALREADY there - running phase $PHASE right now"
  (setsid nice -n 5 sh -c "ESBIN=$ESBIN sh /root/es-smoke-device.sh > /tmp/es-smoke-$PHASE.txt 2>&1; echo \"smoke rc=\$?\" >> /tmp/es-smoke-$PHASE.txt; touch /tmp/es-smoke-$PHASE.done" &)
else
  pgrep -f 'es-watch.sh' >/dev/null && { echo "  a watcher is already running, not doubling up"; exit 0; }
  (setsid nice -n 5 sh -c "BIN=$BIN ESBIN=$ESBIN BUILDDIR=$BUILDDIR BUILDLOG=$LOG MAXS=$MAXS sh /root/es-watch.sh $PHASE > $WATCHLOG 2>&1" &)
fi
sleep 6
echo "  watcher: $(pgrep -cf 'es-watch.sh') proc(s), smoke: $(pgrep -cf 'es-smoke-device.sh') proc(s)"
tail -3 "$WATCHLOG" 2>/dev/null | sed 's/^/     /'
EOS
  ;;
status)
  timeout 90 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV \
    "BIN=$BIN LOG=$LOG WATCHLOG=$WATCHLOG PHASE=$PHASE TREE=$TREE sh -s" <<'EOS'
echo "  tree   : /root/$TREE"
echo "  binary : $([ -x "$BIN" ] && stat -c '%s bytes, linked %y' "$BIN" | cut -c1-52 || echo 'not linked yet')"
echo "  build  : progress $(grep -oE '\[ *[0-9]+%\]' "$LOG" 2>/dev/null | tail -1)  objs started this run=$(grep -c 'Building CXX object' "$LOG" 2>/dev/null)  cc1plus=$(pgrep -cx cc1plus 2>/dev/null || echo 0)  errors=$(grep -c 'error:' "$LOG" 2>/dev/null)"
echo "  current: $(grep -E 'Building CXX|Linking' "$LOG" 2>/dev/null | tail -1 | cut -c1-110)"
if p=$(pgrep -x cc1plus | head -1); [ -n "$p" ]; then
  echo "  compiler: $(awk '/VmRSS/{print int($2/1024)" MB RSS"}' /proc/$p/status)  opts=[$(tr '\0' ' ' < /proc/$p/cmdline | grep -oE '\-[OG][0-9g]*' | tr '\n' ' ')]"
fi
echo "  press  : mem_psi=$(cut -d= -f2 /proc/pressure/memory | head -1 | cut -d' ' -f1)  io_psi=$(cut -d= -f2 /proc/pressure/io | head -1 | cut -d' ' -f1)  $(grep -E 'MemAvailable|^SwapFree' /proc/meminfo | tr '\n' ' ')"
echo "  watch  : $(pgrep -cf es-watch.sh 2>/dev/null || echo 0) watcher(s)   smoke running: $(pgrep -cf es-smoke-device.sh 2>/dev/null || echo 0)   done marker: $(ls /tmp/es-smoke-*.done 2>/dev/null || echo none)"
tail -4 "$WATCHLOG" 2>/dev/null | sed 's/^/     /'
EOS
  ;;
read)
  timeout 90 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV "PHASE=$PHASE WATCHLOG=$WATCHLOG sh -s" <<'EOS'
f=/tmp/es-smoke-$PHASE.txt
[ -f "$f" ] || { echo "  no transcript yet ($f missing)"; echo "  watcher log:"; tail -8 "$WATCHLOG" 2>/dev/null | sed 's/^/     /'; exit 1; }
sed 's/^/  /' "$f"
EOS
  ;;
off)
  timeout 60 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'pkill -f es-watch.sh; sleep 1; echo "  watchers left: $(pgrep -cf es-watch.sh || echo 0)"'
  ;;
*)
  sed -n '1,14p' "$0"
  ;;
esac
