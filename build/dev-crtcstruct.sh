#!/bin/bash
# dev-crtcstruct.sh - print the drmModeCrtc definition from the device's libdrm
# headers so we use the right field names.
set -uo pipefail
DEV=${DEV:-192.168.31.209}
sshpass -p ubuntu ssh -o ConnectTimeout=15 root@$DEV \
  'grep -rn -A16 "struct _drmModeCrtc {" /usr/include/xf86drmMode.h /usr/include/libdrm/xf86drmMode.h 2>/dev/null; echo ---; dpkg -l libdrm-dev 2>/dev/null | tail -2' </dev/null
