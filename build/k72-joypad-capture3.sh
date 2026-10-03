#!/bin/bash
# k72-joypad-capture3.sh - capture the joystick node AND the separate adc-keys
# node for a generous window, then summarise: every EV_KEY code with press and
# release seen, every axis with its min/max, and which codes only ever went one
# way (that is what an inverted or stuck line looks like).
#   DURATION=165 bash k72-joypad-capture3.sh
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
DUR=${DURATION:-165}
JOY=/dev/input/by-path/platform-rocknix-singleadc-joypad-event-joystick
ADC=/dev/input/by-path/platform-adc-keys-event
S() { sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV "$@" </dev/null 2>/dev/null; }

echo "device $DEV  kernel $(S 'uname -r')  capture ${DUR}s"
S 'uname -r | sed "s/^/  loaded kernel: /"
   lsmod | awk "/joypad|polldev/{print \"  module: \" \$1}"
   echo "  module build on card: $(sha256sum /lib/modules/$(uname -r)/extra/rocknix-singleadc-joypad.ko 2>/dev/null | cut -c1-16)"'
S "pkill -x evtest 2>/dev/null; sleep 1
   rm -f /tmp/evjoy.txt /tmp/evadc.txt
   [ -e $JOY ] && ( timeout $DUR evtest --raw $JOY > /tmp/evjoy.txt 2>&1 & )
   [ -e $ADC ] && ( timeout $DUR evtest --raw $ADC > /tmp/evadc.txt 2>&1 & )
   echo '  capturing - press and hold each button ~0.5s, push each stick to the 8 extremes'"
echo "  ... waiting ${DUR}s (window is open now)"
sleep "$((DUR + 8))"

S 'for N in joy adc; do
     F=/tmp/ev$N.txt
     echo "=== $N: $(wc -l < $F 2>/dev/null || echo 0) lines ==="
     python3 - "$F" <<PY
import re,sys
txt=open(sys.argv[1],errors="replace").read()
keys={}; axes={}; rel=set(); pr=set()
for m in re.finditer(r"type 1 \(EV_KEY\), code \d+ \(([A-Z_0-9]+)\) +value (\d)", txt):
    keys.setdefault(m.group(1),[]).append(int(m.group(2)))
    (pr if m.group(2)=="1" else rel).add(m.group(1))
for m in re.finditer(r"type 3 \(EV_ABS\), code \d+ \(([A-Z_0-9]+)\) +value (-?\d+)", txt):
    axes.setdefault(m.group(1),[]).append(int(m.group(2)))
print("  EV_KEY   distinct=%d" % len(keys))
for k,v in sorted(keys.items()):
    ones=sum(1 for x in v if x==1); zeros=sum(1 for x in v if x==0); hs=[x for x in v if x==2]
    flag = "  <= only press, never release" if ones and not zeros else ("  <= only release?! inverted" if zeros and not ones else "")
    print("    %-14s ev=%3d down=%2d up=%2d hold=%d%s" % (k,len(v),ones,zeros,len(hs),flag))
if not keys: print("    (none)")
print("  EV_ABS   distinct=%d" % len(axes))
for k,v in sorted(axes.items()):
    print("    %-8s n=%4d min=%7d max=%7d" % (k,len(v),min(v),max(v)))
if not axes: print("    (none - sticks produced no events)")
print("  MSC_SCAN events: %d" % len(re.findall(r"type 4 \(EV_MSC\)", txt)))
PY
   done
   echo "=== the node advertises these capabilities (input sysfs) ==="
   for d in /sys/class/input/event*; do
     [ -e "$d/device/capabilities/key" ] || continue
     n=$(cat /sys/class/input/$(basename $d)/device/name 2>/dev/null)
     case "$n" in *joypad*|*adc*) echo "  $d = $n"; echo "    abs: $(cat $d/device/capabilities/abs 2>/dev/null)"; echo "    key: $(cat $d/device/capabilities/key 2>/dev/null | cut -c1-100)";; esac
   done
   dmesg | tail -3 | sed "s/^/  dmesg: /"'
echo "=== capture3 done ==="
