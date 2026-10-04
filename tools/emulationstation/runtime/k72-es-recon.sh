#!/bin/bash
# k72-es-recon.sh - everything that decides HOW EmulationStation can be installed
# here, measured on the board rather than guessed:
#   1. desktop GL vs GLES only (ES renders with desktop GL)
#   2. is there an emulationstation package in Ubuntu 26.04 arm64 at all
#   3. are the build deps present (SDL2, freetype, pugixml, rapidyaml, vlc, glm...)
#   4. the budget: free RAM (no swap) and free rootfs space
# Everything runs from a file: inline heredocs through wsl.exe mangle quoting.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}

timeout 60 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'cat > /usr/local/src/r36-glprobe.c' \
  < /mnt/e/ubuntu/packages/gpu-demos/r36-glprobe.c
timeout 280 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
echo "  host=$(hostname) kernel=$(uname -r) mem=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)MB"
mkdir -p /usr/local/src
echo "=== [1] GL capability (this decides whether ES can render at all) ==="
cc -O2 -Wall -o /usr/local/bin/r36-glprobe /usr/local/src/r36-glprobe.c \
   $(pkg-config --cflags --libs egl gbm libdrm) 2>&1 | head -12
if [ -x /usr/local/bin/r36-glprobe ]; then
  /usr/local/bin/r36-glprobe 2>&1 | sed 's/^/  /'
else
  echo "  !! probe did not build - install libegl-dev/libgbm-dev first"
fi
echo "  glvnd/mesa libs: $(ls /usr/lib/aarch64-linux-gnu/ 2>/dev/null | grep -E '^libGL\.so|^libGLESv2\.so|^libvulkan' | tr '\n' ' ')"
echo "  gbm/egl dev    : $(pkg-config --exists egl && echo egl-dev-ok) $(pkg-config --exists gbm && echo gbm-dev-ok)"
echo
echo "=== [2] is there a package? ==="
apt-get update -qq >/dev/null 2>&1
for p in emulationstation emulationstation-de libes-core-dev libsdl2-dev libsdl2-ttf-dev \
         libfreetype-dev libpugixml-dev librapidyaml-dev libvlccore-dev libvlc-dev \
         libgl1-mesa-dev libgles2-mesa-dev libegl1-mesa-dev libasound2-dev libcurl4-openssl-dev \
         libglu1-mesa-dev cmake git build-essential libassimp-dev librsvg2-dev fonts-droid-fallback; do
  c=$(apt-cache policy "$p" 2>/dev/null | awk '/Candidate:/{print $2}')
  printf "  %-26s %s\n" "$p" "${c:-not-in-this-release}"
done
echo
echo "=== [3] budget ==="
echo "  free ram : $(awk '/MemAvailable/{print int($2/1024)" MB"}' /proc/meminfo)   swap: $(swapon --show=SIZE --noheadings 2>/dev/null | tr -d ' \n' || echo 0)"
echo "  rootfs   : $(df -h / | awk 'NR==2{print $4" free of "$2}')"
echo "  nproc    : $(nproc)   load: $(cut -d' ' -f1-3 /proc/loadavg)"
echo "  toolchain: $(cc --version | head -1)"
echo
echo "=== [4] how would it even display? (no X here) ==="
echo "  weston=$(systemctl is-active weston)  xwayland=$(command -v Xwayland || echo none)  weston-backend-drm=$(ls /usr/lib/*/libweston-*/drm-backend.so 2>/dev/null | wc -l)"
echo "  kms device: $(ls /dev/dri 2>/dev/null | tr '\n' ' ')"
echo "  sdl2 kmsdrm support: $(sdl2-config --cflags 2>/dev/null | head -c 40 || echo 'no sdl2-config')"
EOS
echo "=== recon done ==="
