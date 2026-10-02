#!/bin/bash
# dev-retroarch-probe.sh - what does Ubuntu 26.04 actually offer for RetroArch on
# this board, and which input/video/audio backends was it built with?
set -uo pipefail
DEV=${DEV:-192.168.31.209}
S() { sshpass -p ubuntu ssh -o ConnectTimeout=15 root@$DEV "$@" </dev/null 2>/dev/null; }

echo "=== apt availability ==="
S 'apt-get update -qq >/dev/null 2>&1;
   apt-cache policy retroarch retroarch-assets 2>/dev/null | grep -E "^[a-z]|Candidate" | head -8;
   echo "--- cores / related packages:";
   apt-cache search --names-only "^(retroarch|libretro|pcsx|mednafen|mupen|ppsspp|scummvm|retro)" 2>/dev/null | head -30'

echo "=== what RetroArch would pull in (size) ==="
S 'apt-get install -s retroarch 2>/dev/null | grep -E "^(Inst.*libretro|Need to get|[0-9]+ upgraded)" | tail -5;
   apt-get install -s retroarch 2>/dev/null | grep -c "^Inst"'

echo "=== joypad / input devices we have to drive it ==="
S 'ls -l /dev/input/by-path/ 2>/dev/null; cat /proc/bus/input/devices | grep -E "^N:|^H:" | head -12'

echo "=== can it even talk to the display without X/Wayland? ==="
S 'echo "  video candidates:"; ls /usr/lib/aarch64-linux-gnu/ 2>/dev/null | grep -E "libdrm|libgbm|libEGL" | head -5;
   echo "  sdl2: $(apt-cache policy libsdl2-dev 2>/dev/null | awk "/Candidate/{print \$2}")";
   echo "  eglinfo renderer: $(eglinfo -p gbm 2>/dev/null | grep -m1 renderer)"'
