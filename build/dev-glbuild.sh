#!/bin/bash
# dev-glbuild.sh - copy the demo source over and compile it with warnings shown.
set -uo pipefail
DEV=${DEV:-192.168.31.209}
sshpass -p ubuntu scp -q /mnt/e/ubuntu/build/r36-gles2-demo.c "$DEV:/root/r36-gles2-demo.c" || { echo scp failed; exit 1; }
sshpass -p ubuntu ssh -o ConnectTimeout=15 root@$DEV 'cd /root && gcc -O2 -Wall -o r36-gles2-demo r36-gles2-demo.c $(pkg-config --cflags --libs gbm egl glesv2 libdrm) -ldrm; echo "exit=$?"; ls -l --time-style=+%H:%M:%S r36-gles2-demo' </dev/null
