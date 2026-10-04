#!/bin/bash
# k72-facekey-watch.sh - the four face keys are claimed, pulled up and read high,
# yet pressing them produced nothing.  Watch the pad levels at 4 Hz for a window
# while the buttons are pressed, and capture events in parallel, so we can tell
# "the pad never moves" (wrong pin / different wiring) from "the pad moves but the
# driver does not report it".
#   bash k72-facekey-watch.sh [seconds]
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
SECS=${1:-90}
sshpass -p $PW ssh -o ConnectTimeout=15 root@$DEV 'sh -s' <<EOS
DUR=$SECS
mount -t debugfs none /sys/kernel/debug 2>/dev/null
pkill -x evtest 2>/dev/null; sleep 1
rm -f /tmp/faceev.txt /tmp/facelev.txt
( timeout \$DUR evtest /dev/input/by-path/platform-rocknix-singleadc-joypad-event-joystick > /tmp/faceev.txt 2>&1 & )
echo "  sampling \${DUR}s starting \$(date +%H:%M:%S)"
END=\$(( \$(date +%s) + DUR ))
while [ \$(date +%s) -lt \$END ]; do
  echo -n "\$(date +%s.%N | cut -c1-14) " >> /tmp/facelev.txt
  awk '/gpiochip3:/,/gpiochip4:/' /sys/kernel/debug/gpio |
    awk '\$1 ~ /^gpio-/ { for(i=1;i<=NF;i++) if(\$i=="in"||\$i=="out"){ printf "%s=%s ", \$1, \$(i+1); break } }' >> /tmp/facelev.txt
  echo >> /tmp/facelev.txt
  sleep 0.25
done
echo "  samples: \$(wc -l < /tmp/facelev.txt)"
echo "=== distinct level patterns seen on gpio3 ==="
awk '{ \$1=""; print }' /tmp/facelev.txt | sort | uniq -c | sort -rn | head -8 | sed "s/^/  /"
echo "=== did any single line change during the window? ==="
python3 - <<'PY'
import re
rows=[]
for line in open("/tmp/facelev.txt",errors="replace"):
    parts=line.split()
    if not parts or "=" not in line: continue
    rows.append(dict(p.split("=") for p in parts[1:] if "=" in p))
keys=sorted({k for r in rows for k in r})
print("  lines sampled: %d, snapshots: %d" % (len(keys), len(rows)))
changed=[k for k in keys if len({r.get(k) for r in rows if k in r})>1]
print("  CHANGED during window: %s" % (", ".join(changed) if changed else "NONE - every pad stayed put"))
PY
echo "=== events captured in the same window ==="
grep -oE "type [0-9]+ \([A-Z_]+\), code [0-9]+ \([A-Z_0-9]+\), value -?[0-9]+" /tmp/faceev.txt |
  sort | uniq -c | sort -rn | head -14 | sed "s/^/  /"
EOS
echo "=== facekey watch done ==="
