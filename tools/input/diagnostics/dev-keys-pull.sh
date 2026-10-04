#!/bin/bash
# dev-keys-pull.sh - fetch /tmp/keys.log from the device and summarise which
# physical control produced which input code.
set -uo pipefail
DEV=root@192.168.31.210
PW=ubuntu
TS=$(date +%H%M%S)
OUT=/mnt/e/ubuntu/shots/keys-$TS.log

sshpass -p "$PW" scp -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$DEV:/tmp/keys.log" "$OUT" 2>/dev/null
if [ ! -s "$OUT" ]; then
  sshpass -p "$PW" ssh "$DEV" 'cat /tmp/keys.log' </dev/null > "$OUT"
fi
echo "saved: $OUT  ($(wc -l < "$OUT") lines)"
echo
echo "=== per-device event counts ==="
awk '/^event[0-9]+ /{print $1}' "$OUT" | sort | uniq -c | sort -rn
echo
echo "=== key codes seen (device / code / name / presses) ==="
awk '/EV_KEY/{for(i=1;i<=NF;i++) if($i=="code"){c=$(i+1); n=$(i+2)}; gsub(/[(),]/,"",n); if($NF=="1") cnt[c" "n]++} END{for(k in cnt) printf "  %-24s %d\n", k, cnt[k]}' "$OUT" | sort
echo
echo "=== analog axes: min / max observed ==="
awk '/EV_ABS/{for(i=1;i<=NF;i++){if($i=="code"){c=$(i+1)}; if($i=="value"){v=$(i+1)}}; gsub(/[(),]/,"",c); lo[c]=(lo[c]==""||v<lo[c])?v:lo[c]; hi[c]=(hi[c]==""||v>hi[c])?v:hi[c]} END{for(k in lo) printf "  %-10s min=%-6s max=%-6s\n", k, lo[k], hi[k]}' "$OUT" | sort
echo
echo "=== which device produced what (grouped) ==="
awk '/^### /{d=$3} /^event/{print d, $0}' "$OUT" | grep -E "EV_KEY|EV_ABS" | sed -E 's/.*(code [0-9]+ \([A-Z_]+\)).*(value [0-9-]+).*/\1 \2/' | sort | uniq -c | sort -rn | head -30
echo
echo "=== shoulder / trigger support query (no press needed) ==="
sshpass -p "$PW" ssh "$DEV" 'for b in BTN_TL BTN_TR BTN_TL2 BTN_TR2 BTN_MODE BTN_THUMBL BTN_THUMBR; do printf "  %-12s %s\n" "$b" "$(evtest --query /dev/input/event2 EV_KEY $b >/dev/null 2>&1 && echo yes || echo no)"; done; echo "  --- adc-keys(event1) ---"; for b in KEY_VOLUMEUP KEY_VOLUMEDOWN KEY_MENU KEY_BACK KEY_HOME KEY_POWER KEY_SELECT KEY_START; do printf "  %-14s %s\n" "$b" "$(evtest --query /dev/input/event1 EV_KEY $b >/dev/null 2>&1 && echo yes || echo no)"; done; echo "  --- pwrkey(event0) ---"; evtest --query /dev/input/event0 EV_KEY KEY_POWER >/dev/null 2>&1 && echo "  KEY_POWER yes" || echo "  KEY_POWER no"' </dev/null
