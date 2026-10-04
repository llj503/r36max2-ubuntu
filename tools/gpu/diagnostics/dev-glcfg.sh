#!/bin/bash
# dev-glcfg.sh - dump the EGL config list Mesa exposes on the GBM platform, so
# r36-gles2-demo can pick a config whose native visual matches the GBM format.
set -uo pipefail
DEV=${DEV:-192.168.31.209}
S() { sshpass -p ubuntu ssh -o ConnectTimeout=15 root@$DEV "$@" </dev/null 2>/dev/null; }

echo "=== eglinfo -l (configs) ==="
S 'eglinfo -l 2>&1 | head -60'
echo "=== eglinfo (client api + misc) ==="
S 'eglinfo -a 2>&1 | head -40'
echo "=== who holds the drm card ==="
S 'ls -l /dev/dri/; fuser -v /dev/dri/card0 2>&1 | head -5; systemctl is-active getty@tty1'
echo "=== gbm formats ==="
S 'modetest -M rockchip -c 2>&1 | head -20'
