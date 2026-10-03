#!/bin/bash
# k72-es-resume.sh - resume a half-finished EmulationStation build WITHOUT ever re-running
# cmake, and compile whatever is left at -O1 -g0.
#
# Two hard-won rules are encoded here (learned the expensive way at 19:00 today, see
# build/k72-esrn-recover.sh):
#   1. With CMake's "Unix Makefiles" generator every object depends on flags.make, so a
#      `cmake -S -B` reconfigure silently invalidates the whole tree.  This script refuses
#      to run if make would decide to reconfigure, and it never calls cmake itself.
#   2. Lowering the optimiser is done by passing CXX_FLAGS as a *make command line
#      variable* (`-- "CXX_FLAGS=... -O1 -g0"`).  Command-line assignments beat the
#      assignment inside flags.make, GCC honours the last -O/-g, and CXX_DEFINES /
#      CXX_INCLUDES still come from flags.make - so no feature define can be dropped.
#      On this 1 GB board GuiMenu.cpp at -O3 was 705 MB RSS with 27 % CPU efficiency
#      (memory PSI 21, io PSI 71); at -O1 the same file finished in ~5 min with io PSI ~0.
#
#   bash build/k72-es-resume.sh status              # read-only: staleness + pending count
#   bash build/k72-es-resume.sh go                  # resume the build (TREE=es|esrn)
#   TREE=esrn bash build/k72-es-resume.sh go        # same for the ROCKNIX tree
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
TREE=${TREE:-es}
DIR=/root/$TREE
LOG=/tmp/es-$TREE-build.log
cmd=${1:-status}

timeout 300 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV \
  "TREE=$TREE DIR=$DIR LOG=$LOG cmd=$cmd sh -s" <<'EOS'
set -u
B=$DIR/build
EM=$(find $B/es-app/CMakeFiles -maxdepth 1 -type d -name 'emulationstation.dir' 2>/dev/null | head -1)
[ -n "$EM" ] || { echo "  !! no emulationstation.dir under $B - is it configured? (do NOT fix that by re-running cmake here)"; exit 1; }
FM=$EM/flags.make

echo "=== 0) tree ==="
echo "  $DIR   renderer flags: $(sed -n 's/^CXX_DEFINES = //p' "$FM")"
echo "  optimisation now: $(sed -n 's/^CXX_FLAGS = //p' "$FM")"

echo "=== 1) reconfigure risk: make would re-run cmake only if an input is newer than Makefile.cmake ==="
cm=$B/CMakeFiles/Makefile.cmake
newest=$(find $DIR -name CMakeLists.txt -newer "$cm" 2>/dev/null | head -3)
if [ -n "$newest" ]; then
  echo "  !! these CMakeLists are NEWER than Makefile.cmake - a build would reconfigure and invalidate every object:"
  echo "$newest" | sed 's/^/       /'
  [ "${FORCE:-0}" = 1 ] || { echo "  refusing.  Either revert those edits, or run with FORCE=1 after accepting a full rebuild."; exit 1; }
  echo "  (FORCE=1 given - continuing anyway)"
else
  echo "  OK: no cmake input is newer than $(basename $cm) - this build will NOT reconfigure"
fi

echo "=== 2) staleness of what is already built ==="
tot=$(find $B -name '*.o' | wc -l)
stale=$(find $B -name '*.o' ! -newer "$FM" 2>/dev/null | wc -l)
echo "  $tot objects on disk, $stale older than flags.make (0 is what we want)"
echo "  es-app: $(find $B/es-app -name '*.o' | wc -l) built of $(find $DIR/es-app/src -name '*.cpp' | wc -l) sources"

echo "=== 3) pending (dry run; make -n executes nothing) ==="
timeout 150 make -C "$B" -n > /tmp/es-dry-$TREE.log 2>&1
pend=$(grep -c 'Building CXX object' /tmp/es-dry-$TREE.log)
link=$(grep -c 'Linking CXX executable' /tmp/es-dry-$TREE.log)
echo "  pending: $pend CXX objects, $link executable link(s)"
[ "$pend" -gt 0 ] && grep -o 'src/[A-Za-z/]*\.cpp' /tmp/es-dry-$TREE.log | sort -u | head -4 | sed 's/^/       first: /'

echo "=== 4) biggest pending sources (these are the ones that used to thrash) ==="
grep -o 'src/[A-Za-z/]*\.cpp' /tmp/es-dry-$TREE.log | sort -u | sed 's|^|'"$DIR"'/es-app/|' > /tmp/pend.list
n=0
while read -r f; do
  [ -f "$f" ] || continue
  n=$((n+1)); [ $n -gt 200 ] && break
  echo "$(wc -l < "$f") $f"
done < /tmp/pend.list | sort -rn | head -4 | awk '{printf "      %6s lines  %s\n", $1, $2}'

if [ "$cmd" != go ]; then
  echo "  (status only - nothing started; run: TREE=$TREE bash build/k72-es-resume.sh go)"
  exit 0
fi

echo "=== 5) resume detached, -j1, -O1 -g0 appended to the flags from flags.make ==="
pgrep -f "cmake --build|$B" >/dev/null && { echo "  a build is already running, leaving it alone"; exit 0; }
orig=$(sed -n 's/^CXX_FLAGS = //p' "$FM")
new="$orig -O1 -g0"
echo "  passing: CXX_FLAGS=$new"
: > "$LOG"
(setsid nice -n 5 cmake --build "$B" --parallel 1 -- "CXX_FLAGS=$new" >> "$LOG" 2>&1 &)
sleep 15
echo "  cmake procs: $(pgrep -cf "cmake --build")   cc1plus: $(pgrep -cx cc1plus 2>/dev/null || echo 0)"
# read the compiler's own argv out of /proc instead of grepping `ps` output: a
# `ps | grep cc1plus` pipeline matches its own grep process and reports a phantom 1
p=$(pgrep -x cc1plus | head -1)
if [ -n "$p" ]; then
  opts=$(tr '\0' ' ' < /proc/$p/cmdline | grep -oE '\-[OG][0-9g]*' | tr '\n' ' ')
  cur=$(tr '\0' '\n' < /proc/$p/cmdline | grep '\.cpp$' | tail -1)
  echo "  live compiler ($p) on $(basename "${cur:-?}"): opts=[$opts]"
  case " $opts " in *" -O1 "*) echo "  -> -O1 confirmed on the running process" ;; *) echo "  -> !! no -O1 on the running compiler, the override did not land" ;; esac
else
  echo "  (no cc1plus yet - still archiving/linking, check the log in a minute)"
fi
tail -3 "$LOG" | sed 's/^/     /'
echo "  mem: $(grep -E 'MemAvailable|^SwapFree' /proc/meminfo | tr '\n' ' ')"
echo "  poll with: TREE=$TREE bash build/k72-es-resume.sh status"
EOS
