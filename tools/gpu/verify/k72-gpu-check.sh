#!/bin/bash
# k72-gpu-check.sh - non-intrusive GPU check on 7.2.8: EGL/GBM enumeration plus
# the offscreen FBO benchmark (it never calls drmModeSetCrtc, so the console
# stays on screen).
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
S() { sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV "$@" </dev/null 2>/dev/null; }

echo "=== eglinfo (gbm platform) ==="
S 'eglinfo -p gbm 2>/dev/null | grep -aiE "driver name|renderer|version|EGL version" | head -8 | sed "s/^/  /"'
echo "=== panfrost kernel side ==="
S 'dmesg | grep -aiE "panfrost|drm.*initialized|gpu" | head -8 | sed "s/^/  /"'
echo "=== offscreen GLES2 benchmark (light) ==="
S 'cd /root 2>/dev/null; R36_FBO=1 timeout 30 r36-gles2-demo /dev/dri/card0 4 2>&1 | grep -aiE "renderer|version|RESULT|Mpix|error" | sed "s/^/  /"'
echo "=== offscreen GLES2 benchmark (heavy shader) ==="
S 'R36_FBO=1 R36_HEAVY=1 timeout 30 r36-gles2-demo /dev/dri/card0 4 2>&1 | grep -aiE "RESULT|Mpix" | sed "s/^/  /"'
echo "=== gpu devfreq after load ==="
S 'echo "  cur_freq $(cat /sys/class/devfreq/ff400000.gpu/cur_freq) Hz, available: $(cat /sys/class/devfreq/ff400000.gpu/available_frequencies)"'
echo "=== input devices present (joypad expected to be missing) ==="
S 'ls /dev/input/by-path/ | sed "s/^/  /"; grep -c . /proc/bus/input/devices >/dev/null; awk "/^N:/{print \"  \" \$0}" /proc/bus/input/devices'
