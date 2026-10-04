#!/bin/bash
# es-build.sh - EmulationStation the ROCKNIX way: build ROCKNIX/emulationstation-next
# on the board, with the flags ROCKNIX itself uses (projects/ROCKNIX/packages/ui/
# emulationstation/package.mk).
#
#   bash tools/emulationstation/diagnostics/es-build.sh prepare   # verify+fetch the pinned tarball, configure
#   bash tools/emulationstation/diagnostics/es-build.sh build     # detached compile, -j2 (log /tmp/esrn-build.log)
#   bash tools/emulationstation/diagnostics/es-build.sh status    # progress / errors / binary
#   bash tools/emulationstation/diagnostics/es-build.sh check     # GL backend sanity via r36-glprobe
#
# Deliberate differences from ROCKNIX's own recipe:
#   * ENABLE_PULSE=0 - this Ubuntu image has no pulseaudio session running, ALSA does
#   * ROCKNIX's 001-scaling-settings.patch is NOT applied yet (it adds a menu that
#     reads DEVICE_SCANOUT_MAX_RENDER; one thing at a time, add it after it runs)
#   * boost/poppler/fping/p7zip from their DEPENDS list are NOT needed by CMake
#     (checked against this fork's find_package list) - only SDL2/SDL2_mixer/
#     FreeImage/Freetype/CURL/VLC/RapidJSON/ALSA/pugixml/Intl, all already installed
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
DIR=/root/esrn
LOG=/tmp/esrn-build.log
# pinned by ROCKNIX's package.mk, verified against their sha256 before use
REV=cada856d86e3115fbbf0bce09dd761b0ee8fa9fd
SHA=c92eb0fd6e1e2b5fa603391f6c0b540d4fad858664c23321237df32efecf68ad
TAR=esrn-$REV.tar.gz
URL=https://github.com/ROCKNIX/emulationstation-next/archive/$REV.tar.gz

cmd=${1:-status}
case "$cmd" in
prepare)
  timeout 420 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV \
    "REV=$REV SHA=$SHA TAR=$TAR URL=$URL DIR=$DIR sh -s" <<'EOS'
echo "  host=$(hostname)  free=$(df -h / | awk 'NR==2{print $4}')"
cd /root || exit 1
if [ ! -f "/root/$TAR" ]; then
  echo "=== download the pinned tarball ==="
  timeout 300 curl -sSL -o "/root/$TAR" "$URL" || { echo "  !! download failed"; exit 1; }
fi
echo "  sha256 check (against ROCKNIX's PKG_SHA256):"
# no process substitution here: the remote shell is dash, and `<(...)` is a bash
# feature - the first version of this line killed the script right after a passing
# checksum with "Syntax error: \"(\" unexpected"
echo "$SHA  /root/$TAR" > /root/esrn.sha256
sha256sum -c /root/esrn.sha256 2>&1 | sed 's/^/    /'
sha256sum -c /root/esrn.sha256 >/dev/null 2>&1 || { echo "  !! sha mismatch - refusing to build"; exit 1; }
if [ ! -d "$DIR" ]; then
  mkdir -p "$DIR" && tar -xzf "/root/$TAR" -C "$DIR" --strip-components=1 || { echo "  !! extract failed"; exit 1; }
fi
cd "$DIR" || exit 1
echo "  tree: $(find . -name '*.cpp' | wc -l) cpp, submodules present: $(ls external/pugixml 2>/dev/null | wc -l) (pugixml comes from the system)"
grep -n "ROCKNIX" CMakeLists.txt | head -4 | sed 's/^/    /'
echo "=== configure (GLES3 like ROCKNIX, ALSA not pulse) ==="
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release \
  -DGLES3=1 -DROCKNIX=1 -DDISABLE_KODI=1 -DENABLE_FILEMANAGER=0 -DCEC=0 \
  -DENABLE_PULSE=0 -DUSE_SYSTEM_PUGIXML=1 -DENABLE_TTS=OFF 2>&1 | tail -26
echo "  cmake rc=$?"
echo "=== proof of what it decided ==="
grep -E "^GLSystem|^GLES3|^ROCKNIX|^CEC|^ENABLE_PULSE" build/CMakeCache.txt 2>/dev/null | sed 's/^/    /'
grep -o 'DGLES[0-9]*\|DROCKNIX' build/es-core/CMakeFiles/es-core.dir/flags.make 2>/dev/null | sort -u | tr '\n' ' ' | sed 's/^/    defines: /'
echo "    (GLES3 must be listed above; if it says Desktop OpenGL stop and fix)"
EOS
  ;;
build)
  timeout 120 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV \
    "DIR=$DIR LOG=$LOG sh -s" <<'EOS'
cd "$DIR" || { echo "  !! $DIR missing - run: es-build.sh prepare"; exit 1; }
[ -f build/CMakeCache.txt ] || { echo "  !! not configured"; exit 1; }
pgrep -f "cmake --build|cc1plus" >/dev/null && { echo "  a build is already running"; exit 0; }
: > "$LOG"
(setsid nice -n 5 cmake --build build --parallel 2 >> "$LOG" 2>&1 &)
sleep 8
echo "  started; first lines:"
head -6 "$LOG" | sed 's/^/     /'
EOS
  ;;
wait)
  LIMIT=${LIMIT:-500}
  timeout $((LIMIT + 120)) sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV \
    "DIR=$DIR LOG=$LOG LIMIT=$LIMIT sh -s" <<'EOS'
start=$(date +%s)
while :; do
  bin=$(find "$DIR/build" -maxdepth 3 -type f -name emulationstation 2>/dev/null | head -1)
  jobs=$(pgrep -c -f 'cmake --build|cc1plus' 2>/dev/null); jobs=${jobs%%$'\n'*}
  now=$(date +%s)
  if [ -n "$bin" ]; then echo "=== BINARY: $bin ==="; status=0; break; fi
  if [ -z "$jobs" ] || [ "$jobs" = 0 ]; then echo "=== build processes gone, no binary ==="; status=1; break; fi
  if [ $((now - start)) -ge "$LIMIT" ]; then echo "=== still building after ${LIMIT}s ==="; status=2; break; fi
  sleep 20
done
echo "  progress: $(grep -oE '\[ *[0-9]+%\]' "$LOG" 2>/dev/null | tail -1)   errors: $(grep -c 'error:' "$LOG" 2>/dev/null)"
echo "  mem: $(grep -E 'MemAvailable|^SwapFree' /proc/meminfo | tr '\n' ' ')"
grep -E 'error:' "$LOG" 2>/dev/null | head -6 | sed 's/^/     /'
tail -3 "$LOG" 2>/dev/null | sed 's/^/     /'
exit $status
EOS
  rc=$?
  echo "=== wait rc=$rc (0 binary, 1 stopped, 2 still building) ==="
  exit $rc
  ;;
status)
  timeout 90 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV \
    "DIR=$DIR LOG=$LOG sh -s" <<'EOS'
bin=$(find "$DIR/build" -maxdepth 2 -type f -name emulationstation 2>/dev/null | head -1)
alive=$(pgrep -c -f 'cmake --build|cc1plus' 2>/dev/null); alive=${alive%%$'\n'*}
[ -n "$alive" ] || alive=0
errs=$(grep -c 'error:' "$LOG" 2>/dev/null); errs=${errs:-0}
echo "  progress: $(grep -oE '\[ *[0-9]+%\]' "$LOG" 2>/dev/null | tail -1)   build procs=$alive   errors=$errs"
echo "  binary: ${bin:-none yet}"
echo "  mem: $(grep -E 'MemAvailable|^SwapFree' /proc/meminfo | tr '\n' ' ')"
tail -6 "$LOG" 2>/dev/null | sed 's/^/     /'
[ "$errs" != 0 ] && { echo "  --- errors ---"; grep -E 'error:' "$LOG" | head -10 | sed 's/^/     /'; }
[ -n "$bin" ] && exit 2
[ "$errs" != 0 ] && exit 1
[ "$alive" = 0 ] && exit 3
exit 0
EOS
  rc=$?
  echo "=== status rc=$rc (0 building, 1 errors, 2 binary ready, 3 stopped) ==="
  exit $rc
  ;;
check)
  timeout 60 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'mkdir -p /usr/local/src; cat > /usr/local/src/r36-sdlprobe.c' \
    < /mnt/e/ubuntu/packages/gpu-demos/r36-sdlprobe.c || { echo "!! push failed"; exit 1; }
  timeout 280 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
echo "  host=$(hostname)"
cc -O2 -Wall -o /usr/local/bin/r36-sdlprobe /usr/local/src/r36-sdlprobe.c \
   $(sdl2-config --cflags --libs) -ldrm 2>&1 | head -8
[ -x /usr/local/bin/r36-sdlprobe ] || { echo "  !! sdlprobe did not build"; exit 1; }
echo
echo "=== A) weston up -> wayland (with the env an ssh shell does NOT inherit) ==="
XDG_RUNTIME_DIR=/run/wayland WAYLAND_DISPLAY=wayland-0 /usr/local/bin/r36-sdlprobe wayland 2>&1 | sed 's/^/  /'
echo
echo "=== B) weston up -> kmsdrm (expect refusal: weston owns the card) ==="
/usr/local/bin/r36-sdlprobe kmsdrm 2>&1 | sed 's/^/  /'
echo
echo "=== C) stop weston -> kmsdrm on the bare console ==="
echo "  stopping weston (this can take up to its 90s stop timeout)..."
systemctl stop weston 2>/dev/null
i=0; while [ $i -lt 40 ] && pgrep -x weston >/dev/null; do sleep 3; i=$((i+1)); done
echo "  weston=$(systemctl is-active weston) procs=$(pgrep -cx weston) vt=$(fgconsole 2>/dev/null)"
/usr/local/bin/r36-sdlprobe kmsdrm 2>&1 | sed 's/^/  /'
echo
echo "  giving the display back to weston..."
systemctl start weston; sleep 4
echo "  weston=$(systemctl is-active weston)"
EOS
  ;;
*)
  sed -n '1,26p' "$0"
  echo "usage: es-build.sh {prepare|build|status|check}"
  ;;
esac
