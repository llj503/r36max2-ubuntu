#!/bin/bash
# k72-evread.sh - summarise whatever is in /tmp/evjoy.txt + /tmp/evadc.txt on the
# card right now (the window may still be open - evtest flushes per event).
# Reports every key with down/up counts, axes with min/max, and the codes the
# board declares but that were never seen, so the next round can target them.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'for f in /tmp/evjoy.txt /tmp/evadc.txt /tmp/evkbd.txt /tmp/evmouse.txt; do
  echo "=== $f: $(wc -l < $f 2>/dev/null || echo missing) lines, $(grep -c "^Event:" $f 2>/dev/null || echo 0) events ==="
done
python3 - <<PY
import re
EV="/tmp/evjoy.txt"; ADC="/tmp/evadc.txt"; KBD="/tmp/evkbd.txt"; MOU="/tmp/evmouse.txt"
EXPECT=["BTN_DPAD_UP","BTN_DPAD_DOWN","BTN_DPAD_LEFT","BTN_DPAD_RIGHT","BTN_SOUTH","BTN_EAST",
        "BTN_WEST","BTN_NORTH","BTN_SELECT","BTN_START","BTN_MODE","BTN_THUMBL","BTN_THUMBR",
        "BTN_TL","BTN_TR","BTN_TL2","BTN_TR2"]
def scan(path):
    try: txt=open(path,errors="replace").read()
    except OSError: return {}, {}, []      # a missing capture file must not crash the reader
                                           # (the uinput nodes are gone whenever the bridge is
                                           # stopped, and this used to raise ValueError: not
                                           # enough values to unpack (expected 3, got 2))
    keys={}; axes={}; other=[]
    for m in re.finditer(r"type (\d+) \((EV_\w+)\), code (\d+) \(([A-Z_0-9+-]+)\),? +value (-?\d+)", txt):
        t,name,code,val=m.group(2),m.group(4),m.group(3),int(m.group(5))
        if t=="EV_KEY":
            keys.setdefault(name,[0,0,0])            # [up, down, hold]
            keys[name][val if val in (0,1,2) else 0]+=1
        elif t=="EV_ABS":
            axes.setdefault(name,[]).append(val)
        elif t!="EV_SYN":
            other.append((name,code,val))
    return (keys,axes,other)
for label,path in (("joystick (retrogame_joypad)",EV),("adc-keys",ADC),
                   ("KEYBOARD made by r36-keymapper - what the desktop/ES actually sees",KBD),
                   ("MOUSE made by r36-keymapper",MOU)):
    keys,axes,other=scan(path)
    print("--- %s ---" % label)
    print("  EV_KEY  seen=%d" % len(keys))
    for k,v in sorted(keys.items()):
        note=""
        if v[1] and not v[0]: note="   <= pressed but never released (stuck/at-init problem)"
        if v[0] and not v[1]: note="   <= released but never pressed"
        print("    %-14s down=%2d up=%2d hold=%2d%s" % (k,v[1],v[0],v[2],note))
    print("  EV_ABS")
    for k,v in sorted(axes.items()):
        print("    %-8s n=%5d min=%7d max=%7d  span=%d" % (k,len(v),min(v),max(v),max(v)-min(v)))
    if other:
        print("  other events: %s" % ", ".join(sorted(set(o[0] for o in other))))
    missed=[e for e in EXPECT if e not in keys]
    if label.startswith("joystick"):
        print("  declared in DT but NOT seen: %s" % (", ".join(missed) if missed else "(none - all 17 fired)"))
        full=[k for k,v in axes.items() if (max(v)-min(v))>=1200]
        print("  axes with real travel (>=1200): %s" % (", ".join(sorted(full)) if full else "NONE"))
PY
echo "=== live pin state (gpiod) ==="
mount -t debugfs none /sys/kernel/debug 2>/dev/null
grep -iE "rumble|amux" /sys/kernel/debug/gpio 2>/dev/null | sed "s/^/  /"
echo "=== what the booted device tree says about those four lines ==="
J=/proc/device-tree/rocknix-singleadc-joypad
ls $J 2>/dev/null | grep -iE "amux|rumble" | sed "s/^/  node has: /"
for n in amux-a-gpios amux-b-gpios amux-en-gpios rumble-gpio; do
  if [ -e "$J/$n" ]; then
    echo "  $n = $(od -An -tu4 -N12 $J/$n | tr -s " ")"
  else
    echo "  $n MISSING under $J"
  fi
done
dmesg | grep -aiE "joypad|rumble" | tail -4 | sed "s/^/  dmesg: /"'
echo "=== read done ==="
