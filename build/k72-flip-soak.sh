#!/bin/bash
# k72-flip-soak.sh - the churn test (8 x SIGKILL a client) stayed clean, but the
# original stall showed up after ~23 minutes of continuous compositing, so a two
# minute churn is not proof.  This is the long version: MINUTES of weston running
# with a client that keeps attaching and leaving, sampling the kernel's flip/vblank
# counters once a minute and stopping the moment one moves.
#
# It also answers the question the churn log left open - did the client actually
# composite? - by watching weston's accumulated CPU time: an animating EGL client
# should push it up by seconds, an idle compositor by almost nothing.
#
#   MINUTES=12 bash k72-flip-soak.sh
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
MINUTES=${MINUTES:-12}

timeout 120 sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV "cat > /usr/local/bin/r36-flip-soak.sh" \
  < /mnt/e/ubuntu/build/r36-flip-soak-device.sh 2>/dev/null || {
  echo "  (pushing the device-side script failed; aborting)"; exit 1; }
timeout $((MINUTES * 60 + 240)) sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV \
  "MINUTES=$MINUTES sh /usr/local/bin/r36-flip-soak.sh" 2>&1 | tail -60
echo "=== soak finished ==="
