#!/bin/bash
# k72-es-prepare.sh - get batocera-emulationstation configured on the board.
#
# Why this fork (measured, not guessed):
#   * it has a real desktop-GL path: CMake option GL -> find_package(OpenGL), and
#     this board's Mesa gives GL 3.1 "Mali-G31 MC1 (Panfrost)" over GBM with a
#     working eglSwapBuffers (build/r36-glprobe.c proved it)
#   * it is the front-end Batocera ships on RK3326 handhelds, so gamepad/theme
#     behaviour matches what the hardware is
#   * one submodule only (pugixml), and libpugixml-dev exists here (USE_SYSTEM_PUGIXML)
#
# apt lesson reused: one unknown package name makes apt install NOTHING and still
# exit 0, so every name is filtered through apt-cache policy first.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 560 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
echo "  host=$(hostname) disk=$(df -h / | awk 'NR==2{print $4}') ram=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)MB"
DEPS="git cmake build-essential pkg-config libsdl2-dev libsdl2-mixer-dev libfreetype-dev \
libfreeimage-dev libcurl4-openssl-dev rapidjson-dev libasound2-dev libgl1-mesa-dev \
libegl1-mesa-dev libgbm-dev libudev-dev libvlc-dev libvlccore-dev libpugixml-dev \
libfribidi-dev fonts-droid-fallback vlc-bin libdrm-dev libgles2-mesa-dev"
HAVE=""
for p in $DEPS; do
  c=$(apt-cache policy "$p" 2>/dev/null | awk '/Candidate:/{print $2}')
  case "$c" in ""|none) echo "  skip (not in this release): $p";; *) HAVE="$HAVE $p";; esac
done
echo "=== [1] installing ${#HAVE} chars of package names ==="
apt-get update -qq 2>&1 | tail -2
DEBIAN_FRONTEND=noninteractive apt-get install -y -q $HAVE 2>&1 | tail -6
ok=0; tot=0
for p in $HAVE; do
  tot=$((tot + 1))
  dpkg -l "$p" 2>/dev/null | grep -q '^ii' && ok=$((ok + 1)) || echo "  !! still missing: $p"
done
echo "  confirmed installed: $ok/$tot"

echo "=== [2] swap for the compile (972 MB RAM, no swap, some ES TUs are heavy) ==="
if [ -n "$(swapon --show=SIZE --noheadings 2>/dev/null)" ]; then
  echo "  swap already present: $(swapon --show=SIZE --noheadings | tr '\n' ' ')"
elif [ ! -f /swap.es.img ]; then
  fallocate -l 1G /swap.es.img && chmod 600 /swap.es.img && mkswap /swap.es.img >/dev/null && swapon /swap.es.img
  echo "  added /swap.es.img (1G, NOT in /etc/fstab - removable with swapoff+rm)"
fi
echo "  now: $(free -m | awk '/^Swap/{print "total="$2"MB used="$3"MB"}')"

echo "=== [3] source ==="
cd /root || exit 1
if [ ! -d /root/es/.git ]; then
  timeout 300 git clone --depth 1 --recursive https://github.com/batocera-linux/batocera-emulationstation.git /root/es 2>&1 | tail -4
fi
cd /root/es || exit 1
echo "  rev=$(git rev-parse --short HEAD)  files=$(find . -name '*.cpp' | wc -l) cpp, submodules: $(git submodule status | wc -l)"
git submodule status | sed 's/^/     /'
du -sh /root/es 2>/dev/null | sed 's/^/  size: /'

echo "=== [4] configure (desktop GL, no CEC, system pugixml) ==="
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DGL=ON -DCEC=OFF -DBATOCERA=OFF \
      -DUSE_SYSTEM_PUGIXML=ON -DENABLE_TTS=OFF -DENABLE_FILEMANAGER=OFF 2>&1 | tail -30
echo "  cmake rc=$?"
grep -E "Graphics API|-- (Checking|Found).*(OpenGL|SDL2|VLC|FreeImage|RapidJSON|Freetype|CURL)" /root/es/build/CMakeFiles/CMakeConfigureLog.yaml 2>/dev/null | head -8 | sed 's/^/     /'
EOS
echo "=== prepare finished ==="
