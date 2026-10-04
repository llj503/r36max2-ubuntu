#!/bin/bash
# dev-glprobe.sh - build and run egl-probe on the R36 Max 2
set -uo pipefail
DEV=${DEV:-192.168.31.209}
S() { sshpass -p ubuntu ssh -o ConnectTimeout=15 root@$DEV "$@" </dev/null 2>/dev/null; }

sshpass -p ubuntu scp -q /mnt/e/ubuntu/packages/gpu-demos/egl-probe.c "$DEV:/root/egl-probe.c" || { echo "scp failed"; exit 1; }
echo "=== build ==="
S 'cd /root && gcc -O2 -o egl-probe egl-probe.c $(pkg-config --cflags --libs gbm egl glesv2 libdrm) -ldrm 2>&1 | head -30; ls -l egl-probe 2>/dev/null'
echo "=== run ==="
S 'cd /root && ./egl-probe /dev/dri/card0 2>&1'
