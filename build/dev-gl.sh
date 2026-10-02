#!/bin/bash
# dev-gl.sh - (1) make unmistakable noise so the user can confirm audio, (2) get
# the GL stack in place and see what mesa/panfrost reports.
set -uo pipefail
DEV=${DEV:-192.168.31.209}
S() { sshpass -p ubuntu ssh -o ConnectTimeout=10 root@$DEV "$@" </dev/null 2>/dev/null; }

echo "=== 1. 音量确认 + 放一段明显的声音 ==="
S '/usr/local/sbin/r36-audio
   amixer -c 0 sget Master | grep -E "Front Left:" | sed "s/^/  /"
   echo "  播放: 3 秒语音声道 + 2 秒 660Hz + 2 秒 1320Hz"
   timeout 3 speaker-test -D plughw:0,0 -c 2 -t wav -l 1 >/dev/null 2>&1
   sleep 1
   timeout 2 speaker-test -D plughw:0,0 -c 2 -t sine -f 660 -l 1 >/dev/null 2>&1
   sleep 1
   timeout 2 speaker-test -D plughw:0,0 -c 2 -t sine -f 1320 -l 1 >/dev/null 2>&1
   echo "  放完了"'

echo "=== 2. GL 用户态组件 ==="
S 'tail -1 /root/setup.log; pgrep -x apt-get >/dev/null && echo "  (dev baseline still installing, waiting is fine)" || echo "  dev baseline done"
   export DEBIAN_FRONTEND=noninteractive
   apt-get -y -qq install mesa-utils glmark2 libegl1 libgles2 libgbm1 >/dev/null 2>&1
   for b in es2_info es2gears glmark2 glmark2-es2 glmark2-drm glxinfo; do printf "  %-12s %s\n" "$b" "$(command -v $b || echo -)"; done
   echo "  mesa: $(dpkg -l | awk "/^ii  mesa-utils /{print \$3}")"'

echo "=== 3. EGL/GL 到底能不能起来（surfaceless，不动控制台）==="
S 'echo "--- es2_info (surfaceless) ---"
   EGL_PLATFORM=surfaceless timeout 20 es2_info 2>&1 | head -22 | sed "s/^/  /"
   echo "--- eglinfo ---"
   (command -v eglinfo >/dev/null && EGL_PLATFORM=surfaceless timeout 15 eglinfo 2>&1 | head -18 | sed "s/^/  /") || echo "  eglinfo not installed"
   echo "--- dri nodes + perf ---"
   ls -l /dev/dri/ | sed "s/^/  /"
   cat /sys/kernel/debug/dri/0/name 2>/dev/null | sed "s/^/  /"
   grep -iE "panfrost|gpu" /sys/class/devfreq/*/name 2>/dev/null | sed "s/^/  /"'
