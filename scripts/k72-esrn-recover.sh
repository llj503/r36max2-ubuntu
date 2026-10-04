#!/bin/bash
# k72-esrn-recover.sh - undo the damage of my own flag experiment, then build the
# remaining objects at -O1 without ever re-running cmake again.
#
# What went wrong: k72-esrn-fastmenu.sh added a per-source -O1 tweak and re-ran cmake.
# The root-scope set_source_files_properties did NOT reach the file (grep for -O1 in the
# generated rules: 0 hits), but the reconfigure DID rewrite flags.make - and CMake's
# Makefile generator makes every object depend on flags.make.  So 141 finished objects
# (all of es-core + 34 of es-app) became "out of date" and the rebuild restarted from
# 40%.  Lesson: with a Makefile-generator tree, any `cmake -S -B` is a full rebuild.
#
# Recovery: the .o files were never deleted, only their timestamps went stale.  If the
# regenerated flags.make is byte-identical to the pre-reconfigure one (proved by diff,
# not assumed), the objects are still exactly what the current rules would produce, so
# touching them newer than the makefiles is safe and correct.
#
# Then, for the -O1 goal WITHOUT another reconfigure: pass CXX_FLAGS as a make command
# line variable (`cmake --build ... -- CXX_FLAGS=...`).  Command-line assignments beat
# flags.make's assignment, the override is appended (GCC takes the last -O / -g), and
# CXX_DEFINES / CXX_INCLUDES still come from flags.make untouched - so no define can be
# silently dropped.
#
#   bash scripts/k72-esrn-recover.sh          # recover + resume at -O1
#   bash scripts/k72-esrn-recover.sh check    # read-only: counts, diff, pending list
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
D=/root/esrn
LOG=/tmp/esrn-build.log
EMO=es-app/CMakeFiles/emulationstation.dir

cmd=${1:-go}
REMOTE="D=$D LOG=$LOG EMO=$EMO sh -s"

if [ "$cmd" = check ]; then
  timeout 150 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV "$REMOTE" <<'EOS'
echo "=== objects on disk by directory ==="
for d in es-app es-core external; do
  echo "  $d: $(find $D/build/$d -name '*.o' 2>/dev/null | wc -l) .o   newest=$(find $D/build/$d -name '*.o' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2- | xargs -r stat -c '%y' 2>/dev/null | cut -c1-19)"
done
echo "=== flags.make timestamps (what invalidates objects) ==="
find $D/build -name flags.make -printf '  %TY-%Tm-%Td %TH:%TM:%TS  %p\n' | sort | head -6
echo "=== newest object vs its flags.make: is anything stale? ==="
o=$(find $D/build -name '*.o' -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)
echo "  newest object: ${o:-none}"
[ -n "$o" ] && { f=$(dirname "$o"); while [ "$f" != "$D/build" ] && [ ! -f "$f/flags.make" ]; do f=$(dirname "$f"); done; echo "  its flags.make: $(stat -c '%y' "$f/flags.make" 2>/dev/null | cut -c1-19)"; [ "$o" -nt "$f/flags.make" ] && echo "  -> UP TO DATE" || echo "  -> STALE (would rebuild)"; }
echo "=== live build ==="
ps -eo pid,etimes,rss,args --sort=-rss | grep -E 'cc1plus|cmake --build' | grep -v grep | cut -c1-100 | head -4
echo "=== log tail ==="
tail -3 "$LOG" 2>/dev/null | sed 's/^/     /'
EOS
  exit $?
fi

timeout 420 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV "$REMOTE" <<'EOS'
set -u
cd "$D" || { echo "  !! $D missing"; exit 1; }
EM=$D/build/$EMO

echo "=== 1) stop the rebuild (build processes only) ==="
pkill -f "cmake --build $D/build" 2>/dev/null
sleep 2
pkill -x cc1plus 2>/dev/null; pkill -x as 2>/dev/null
sleep 2
echo "  left: cmake=$(pgrep -cf "cmake --build $D/build") cc1plus=$(pgrep -cx cc1plus)"

echo "=== 2) save flags.make, remove the ineffective tweak, reconfigure ONE last time ==="
cp "$EM/flags.make" /tmp/flags.make.before
if [ -f CMakeLists.txt.orig ]; then
  cp CMakeLists.txt.orig CMakeLists.txt
  echo "  CMakeLists.txt restored (tweak lines now: $(grep -c set_source_files_properties CMakeLists.txt))"
fi
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release \
  -DGLES3=1 -DROCKNIX=1 -DDISABLE_KODI=1 -DENABLE_FILEMANAGER=0 -DCEC=0 \
  -DENABLE_PULSE=0 -DUSE_SYSTEM_PUGIXML=1 -DENABLE_TTS=OFF > /tmp/esrn-cmake.log 2>&1
echo "  cmake rc=$? $(tail -1 /tmp/esrn-cmake.log)"

echo "=== 3) PROOF the flags did not change (otherwise reusing objects would be a lie) ==="
if diff -q /tmp/flags.make.before "$EM/flags.make" > /dev/null; then
  echo "  flags.make is byte-identical to the pre-experiment copy:"
  sed 's/^/      /' "$EM/flags.make" | cut -c1-150
else
  echo "  !! flags.make CHANGED - refusing to reuse objects, the rebuild must finish honestly"
  diff /tmp/flags.make.before "$EM/flags.make" | head -12 | sed 's/^/      /'
  exit 1
fi

echo "=== 4) restamp every existing object (and archive) to now ==="
n=$(find build -name '*.o' | wc -l)
find build -name '*.o' -exec touch {} +
find build -name '*.a' -exec touch {} +
echo "  touched $n objects; still on disk: $(find build -name '*.o' | wc -l)"

echo "=== 5) build the -O1 override string verbatim from flags.make ==="
orig=$(sed -n 's/^CXX_FLAGS = //p' "$EM/flags.make")
new="$orig -O1 -g0"
echo "  will pass:  $new"
echo "  (appended: GCC honours the LAST -O and the LAST -g, so this only changes optimisation)"

echo "=== 6) dry run: what is actually left (make -n executes nothing) ==="
timeout 120 cmake --build build --parallel 1 -- -n > /tmp/esrn-dry.log 2>&1
echo "  remaining: $(grep -c 'Building CXX' /tmp/esrn-dry.log) CXX, $(grep -c 'Building C object' /tmp/esrn-dry.log) C, $(grep -c 'Linking CXX executable' /tmp/esrn-dry.log) link(s)"
grep -o 'src/[A-Za-z/]*/[A-Za-z]*\.cpp' /tmp/esrn-dry.log | sort -u | head -12 | sed 's/^/    /'
echo "  GuiMenu.cpp in the list: $(grep -c 'GuiMenu.cpp' /tmp/esrn-dry.log) hit(s)"

echo "=== 7) resume detached at -O1, one job ==="
cp -f "$LOG" /tmp/esrn-build.prev.log 2>/dev/null
: > "$LOG"
(setsid nice -n 5 cmake --build build --parallel 1 -- "CXX_FLAGS=$new" >> "$LOG" 2>&1 &)
sleep 15
echo "  procs: $(pgrep -cf "cmake --build $D/build") cmake, $(pgrep -cx cc1plus) cc1plus"
echo "  running command has -O1: $(ps -eo args | grep -c 'CXX_FLAGS=.*-O1')"
tail -4 "$LOG" | sed 's/^/     /'
echo "  mem: $(grep -E 'MemAvailable|^SwapFree' /proc/meminfo | tr '\n' ' ')"
EOS
