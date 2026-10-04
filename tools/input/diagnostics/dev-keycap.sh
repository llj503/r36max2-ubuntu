#!/bin/bash
# dev-keycap.sh - detached capture of every input event for ${1:-150}s.
# (evtest in Ubuntu has no --raw; plain `evtest <dev>` prints one Event: line each.)
set -uo pipefail
DEV=root@192.168.31.210
PW=ubuntu
DUR=${1:-150}
S() { sshpass -p "$PW" ssh -o ConnectTimeout=10 "$DEV" "$@" </dev/null; }

cat > /tmp/keycap.sh <<'EOS'
#!/bin/sh
DUR=${1:-150}
: > /tmp/keys.log
for d in /dev/input/event*; do
    n=$(basename "$d")
    name=$(awk -v h="$n" 'BEGIN{p=""} /^N:/{name=$0} /^H:/ && $0 ~ h {print name; exit}' /proc/bus/input/devices | sed 's/.*Name="//;s/"$//')
    printf '### %s = %s\n' "$d" "${name:-?}" >> /tmp/keys.log
    (timeout "$DUR" evtest "$d" 2>/dev/null | grep --line-buffered "^Event:" | sed "s|^|$n |" >> /tmp/keys.log) &
done
wait
printf '### capture finished %s\n' "$(date -Is)" >> /tmp/keys.log
EOS
sshpass -p "$PW" scp -q /tmp/keycap.sh "$DEV:/usr/local/sbin/r36-keycap"
# NOTE: never `pkill -f "evtest ..."` here - the pattern matches this very remote
# bash -c command line and pkill kills its own parent (documented WSL pitfall).
S 'chmod 755 /usr/local/sbin/r36-keycap; pkill -x evtest; sleep 1; setsid nohup /usr/local/sbin/r36-keycap '"$DUR"' </dev/null >/dev/null 2>&1 & exit 0'
sleep 4
S 'echo "evtest procs: $(pgrep -cx evtest)"; wc -l /tmp/keys.log; head -8 /tmp/keys.log'
echo "=== joystick tools (jstest is not in resolute; evtest on event2 covers ABS_*) ==="
S 'command -v jstest || echo "  no jstest - will read /dev/input/event2 ABS_ events instead"'
echo "CAPTURE_RUNNING_FOR=${DUR}s"
