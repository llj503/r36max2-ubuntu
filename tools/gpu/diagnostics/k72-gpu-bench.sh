#!/bin/bash
# k72-gpu-bench.sh - run the GLES2 benchmark on 7.2.8 using the binary that is
# actually on this card (/root/, installed during the GPU session; v19 images
# put it in /usr/local/bin).
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
S() { sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV "$@" </dev/null 2>/dev/null; }

BIN=$(S 'for p in /usr/local/bin/r36-gles2-demo /root/r36-gles2-demo; do [ -x "$p" ] && { echo "$p"; exit; }; done')
echo "binary: ${BIN:-NOT FOUND}"
[ -n "$BIN" ] || exit 1

echo "=== offscreen, light shader ==="
S "R36_FBO=1 $BIN /dev/dri/card0 4 2>&1 | grep -aiE 'renderer|version|RESULT|Mpix|error' | sed 's/^/  /'"
echo "=== offscreen, heavy shader ==="
S "R36_FBO=1 R36_HEAVY=1 $BIN /dev/dri/card0 4 2>&1 | grep -aiE 'RESULT|Mpix' | sed 's/^/  /'"
echo "=== gpu frequency under load (sampled while running) ==="
S "(for i in 1 2 3 4 5 6; do cat /sys/class/devfreq/ff400000.gpu/cur_freq; sleep 0.5; done) > /tmp/f.txt & R36_FBO=1 $BIN /dev/dri/card0 3 >/dev/null 2>&1; wait; sort -n /tmp/f.txt | uniq -c | sed 's/^/  /'"
echo "=== scan-out path (6s of animation on the panel, then hands the screen back) ==="
S "R36_HOLD=6 $BIN /dev/dri/card0 6 2>&1 | grep -aiE 'RESULT|restore|cfg cand|error' | sed 's/^/  /'"
echo "=== console back? ==="
S 'echo "  tty1 owner: $(ps -o comm= -t tty1 2>/dev/null | tr "\n" " ")"; dmesg | tail -3 | sed "s/^/    /"'
