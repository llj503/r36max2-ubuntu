#!/bin/bash
# find-esbin.sh - locate the EmulationStation executable the way it actually is, not
# the way the ROCKNIX tree happened to name it.
#
# Why: es-watch.sh reported "build processes gone and NO binary" after 2123s, but its own
# log tail shows "[100%] Built target i18n" - that is a COMPLETED build.  batocera's
# CMakeLists sets its own output directory, so /root/es/build/es-app/emulationstation was
# an assumption copied from the esrn tree.  An assumed artifact path is exactly the kind
# of thing that turns success into a false failure.
#
# Everything remote lives in a quoted heredoc feeding `sh -s`; no local expansion, and no
# nested quotes inside the command string (that is what made the last probe print the WSL
# hostname instead of the board's).
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
DIR=${DIR:-/root/es}

timeout 120 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV "DIR=$DIR sh -s" <<'EOS'
echo "  host=$(hostname)  uptime=$(cut -d' ' -f1 /proc/uptime)s  boot_id=$(cat /proc/sys/kernel/random/boot_id)"
echo "=== every file named emulationstation under $DIR (and its repo root) ==="
find "$DIR" -type f -name 'emulationstation*' -printf '  %10s  %TY-%Tm-%Td %TH:%TM  %p\n' 2>/dev/null | sort -k4 | head -12
echo "=== any executable > 5 MB built in the last 2 hours ==="
find "$DIR" -type f -perm -u+x -size +5M -newermt '-2 hours' -printf '  %10s  %TH:%TM  %p\n' 2>/dev/null | head -8
echo "=== what the link step said ==="
grep -E 'Linking CXX executable|Built target' /tmp/es-es-build.log 2>/dev/null | tail -6 | sed 's/^/     /'
echo "=== the generator's own answer: where does the target go? ==="
grep -E '^(TARGET_OUTPUT|CMAKE_RUNTIME_OUTPUT)' "$DIR/build/es-app/CMakeFiles/emulationstation.dir/flags.make" 2>/dev/null | sed 's/^/     /'
grep -rhoE 'set\(CMAKE_RUNTIME_OUTPUT_DIRECTORY[^)]*\)' "$DIR/CMakeLists.txt" "$DIR/es-app/CMakeLists.txt" 2>/dev/null | sed 's/^/     /'
echo "=== build still running? ==="
echo "  cmake=$(pgrep -cf 'cmake --build')  cc1plus=$(pgrep -cx cc1plus)  ld=$(pgrep -cx ld)  make=$(pgrep -cx make)"
echo "=== watcher / smoke state ==="
echo "  es-watch procs: $(pgrep -cf es-watch.sh)"
ls -l /tmp/es-smoke-A.txt /tmp/es-smoke-A.done 2>/dev/null | sed 's/^/     /' || echo "     no transcript yet"
echo "=== progress tail ==="
tail -3 /tmp/es-es-build.log 2>/dev/null | sed 's/^/     /'
echo "  errors: $(grep -c 'error:' /tmp/es-es-build.log 2>/dev/null)   oom kills: $(dmesg 2>/dev/null | grep -ci 'oom-kill')"
EOS
