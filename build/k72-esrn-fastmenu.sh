#!/bin/bash
# k72-esrn-fastmenu.sh - stop the -O3 compile of GuiMenu.cpp on this 1 GB board and
# rebuild that single translation unit at -O1 -g0.
#
# Why: GuiMenu.cpp is 7052 lines and its cc1plus settles at ~705 MB RSS.  With 1 GB of
# RAM total, MemAvailable drops to ~66 MB and the compiler starts swapping itself:
# measured 12 s of CPU in 45 s of wall time, /proc/pressure/memory avg10 ~21,
# /proc/pressure/io avg10 ~71 (i.e. 70 % of every task's wall time is blocked on
# memory-driven I/O).  It was not "a slow file", it was a thrash.  -O1/-g0 keeps the
# peak working set far smaller; a GUI-menu TU does not need -O3 on a handheld.
#
# Nothing already compiled is thrown away: the 34 finished es-app objects and all of
# es-core keep their -O3 code (CMake's Makefile generator does not invalidate objects
# when flags change).  A --dry-run is printed first so this is verifiable, not assumed.
#
#   bash build/k72-esrn-fastmenu.sh          # switch + restart the build
#   bash build/k72-esrn-fastmenu.sh undo     # restore the untouched CMakeLists
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
DIR=/root/esrn
LOG=/tmp/esrn-build.log
MARK='# r36max2-lowmem-tweak'

cmd=${1:-go}

if [ "$cmd" = undo ]; then
  timeout 90 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV "MARK='$MARK' DIR=$DIR sh -s" <<'EOS'
cd "$DIR" || exit 1
[ -f CMakeLists.txt.orig ] && { cp CMakeLists.txt.orig CMakeLists.txt && echo "  restored original CMakeLists.txt"; }
grep -c "$MARK" CMakeLists.txt | sed 's/^/  tweak lines still present: /'
EOS
  exit 0
fi

timeout 420 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV \
  "DIR=$DIR LOG=$LOG MARK='$MARK' sh -s" <<'EOS'
set -u
cd "$DIR" || { echo "  !! $DIR missing"; exit 1; }

echo "=== 1) stop the thrashing compile (build only; nothing else is touched) ==="
pkill -f "cmake --build $DIR/build" 2>/dev/null
sleep 2
pkill -x cc1plus 2>/dev/null
pkill -x as 2>/dev/null
sleep 2
echo "  remaining: cmake=$(pgrep -cf "cmake --build $DIR/build") cc1plus=$(pgrep -cx cc1plus)"
# a kill mid-write can leave a half-written object newer than its source, which make
# would happily reuse and then fail to link.  Remove it.
rm -f "$DIR/build/es-app/CMakeFiles/emulationstation.dir/src/guis/GuiMenu.cpp.o"
echo "  stale GuiMenu.cpp.o removed: $([ -f "$DIR/build/es-app/CMakeFiles/emulationstation.dir/src/guis/GuiMenu.cpp.o" ] && echo NO || echo yes)"

echo "=== 2) insert the per-file flag tweak (idempotent, backed up once) ==="
if grep -q "$MARK" CMakeLists.txt; then
  echo "  already present, not duplicating"
else
  [ -f CMakeLists.txt.orig ] || cp CMakeLists.txt CMakeLists.txt.orig
  awk -v MARK="$MARK" '
    !done && /^add_subdirectory\("es-app"\)/ {
      print  MARK " - see build/k72-esrn-fastmenu.sh in the host repo for the reason";
      print  "set_source_files_properties(\"${CMAKE_SOURCE_DIR}/es-app/src/guis/GuiMenu.cpp\"";
      print  "  PROPERTIES COMPILE_OPTIONS \"-O1;-g0\")";
      print  "";
      done=1
    }
    { print }
  ' CMakeLists.txt > CMakeLists.txt.new && mv CMakeLists.txt.new CMakeLists.txt
  echo "  inserted before add_subdirectory(\"es-app\"):"
  grep -n -B1 -A2 'set_source_files_properties' CMakeLists.txt | sed 's/^/    /'
fi

echo "=== 3) reconfigure with the same cache and options ==="
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release \
  -DGLES3=1 -DROCKNIX=1 -DDISABLE_KODI=1 -DENABLE_FILEMANAGER=0 -DCEC=0 \
  -DENABLE_PULSE=0 -DUSE_SYSTEM_PUGIXML=1 -DENABLE_TTS=OFF > /tmp/esrn-cmake.log 2>&1
echo "  cmake rc=$?  $(tail -2 /tmp/esrn-cmake.log | tr '\n' ' ')"
echo "  -O1 present in the generated rules: $(grep -c '\-O1' build/es-app/CMakeFiles/emulationstation.dir/build.make) line(s)"
grep -o '\-O[0-9g][^ ]* [^ ]*GuiMenu.cpp.o' build/es-app/CMakeFiles/emulationstation.dir/build.make | head -2 | sed 's/^/    /'

echo "=== 4) dry run: exactly what make thinks it must do next ==="
timeout 120 cmake --build build --parallel 1 -- -n > /tmp/esrn-dry.log 2>&1
echo "  would compile $(grep -c 'Building CXX' /tmp/esrn-dry.log) CXX objects, $(grep -c 'Linking CXX executable' /tmp/esrn-dry.log) link(s)"
grep -o 'src/guis/[A-Za-z]*\.cpp' /tmp/esrn-dry.log | sort -u | tr '\n' ' ' | sed 's/^/    pending: /;s/$/\n/'

echo "=== 5) restart detached, one job, log preserved ==="
cp -f "$LOG" /tmp/esrn-build.prev.log 2>/dev/null
: > "$LOG"
(setsid nice -n 5 cmake --build build --parallel 1 >> "$LOG" 2>&1 &)
sleep 12
echo "  started: $(pgrep -cf 'cmake --build' ) cmake proc(s)"
tail -3 "$LOG" | sed 's/^/     /'
echo "  mem now: $(grep -E 'MemAvailable|^SwapFree' /proc/meminfo | tr '\n' ' ')"
echo "=== done; re-arm the relay:  LIMIT=560 ... k72-esrn-onbuild.sh env PHASE=A WAIT=25 bash k72-es-smoke.sh ==="
EOS
