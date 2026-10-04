#!/bin/bash
# dev-glbench.sh - rebuild the demo, then measure (a) scan-out frame rate and
# (b) offscreen FBO throughput with a light and a shader-heavy pass.
set -uo pipefail
DEV=${DEV:-192.168.31.209}
S() { sshpass -p ubuntu ssh -o ConnectTimeout=15 root@$DEV "$@" </dev/null 2>/dev/null; }

bash /mnt/e/ubuntu/scripts/dev-glbuild.sh | tail -3

run() {  # $1 = label, rest = env assignments
  local label="$1"; shift
  echo "=== $label ==="
  S "cd /root && $* ./r36-gles2-demo /dev/dri/card0 5 2>&1 | grep -E 'fps|RESULT|renderer|version|config|gl error|Mpix|FBO|error' | sed 's/^/  /'"
}

run "scan-out (GBM surface + page flips)"  R36_HOLD=0
run "offscreen FBO, light shader"          R36_FBO=1
run "offscreen FBO, heavy shader"          R36_FBO=1 R36_HEAVY=1
echo "=== gpu devfreq ==="
S 'for f in /sys/class/devfreq/ff400000.gpu/*; do echo -n "  $(basename $f): "; cat $f 2>/dev/null | tr "\n" " "; echo; done'
