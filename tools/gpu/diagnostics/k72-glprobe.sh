#!/bin/bash
# k72-glprobe.sh - run only the GL capability probe (fast, for re-checking after a
# kernel/Mesa change).  The recon script does the same thing as part of a bigger
# survey; this one exists so the answer is one command away.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
# push + rebuild every time: this probe is the thing you reach for after a kernel
# or Mesa bump, and running a stale binary from /usr/local/bin is how you end up
# trusting an old answer
timeout 60 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'mkdir -p /usr/local/src; cat > /usr/local/src/r36-glprobe.c' \
  < /mnt/e/ubuntu/packages/gpu-demos/r36-glprobe.c || { echo "!! push failed"; exit 1; }
timeout 150 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
echo "  host=$(hostname) kernel=$(uname -r) mesa=$(dpkg -l 2>/dev/null | awk '/^ii  libgl1-mesa-dri/{print $3}')"
cc -O2 -Wall -o /usr/local/bin/r36-glprobe /usr/local/src/r36-glprobe.c \
   $(pkg-config --cflags --libs egl gbm libdrm) 2>&1 | head -8
[ -x /usr/local/bin/r36-glprobe ] || { echo "  !! build failed"; exit 1; }
/usr/local/bin/r36-glprobe 2>&1 | sed 's/^/  /'
echo
echo "  vulkan icds: $(ls /usr/share/vulkan/icd.d/ 2>/dev/null | tr '\n' ' ')"
if command -v vulkaninfo >/dev/null 2>&1; then vulkaninfo --summary 2>/dev/null | head -8 | sed 's/^/     /'; else echo "  (no vulkaninfo installed)"; fi
EOS
echo "=== glprobe done ==="
