#!/bin/bash
# k72-rumble-test.sh - drive the FF rumble path end to end with the corrected
# polarity: upload an FF_RUMBLE effect, play it for DUR ms while sampling the
# pin level out of debugfs, then stop it and remove the effect.
# Proves BOTH directions: logical 1 must reach the pad high (motor spins) and
# logical 0 must bring it back low (motor silent).  Needs no extra packages.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
DUR=${1:-700}
timeout 60 sshpass -p $PW ssh -o ConnectTimeout=15 root@$DEV 'sh -s' <<EOS
DUR=$DUR
mount -t debugfs none /sys/kernel/debug 2>/dev/null
DEVNODE=/dev/input/by-path/platform-rocknix-singleadc-joypad-event-joystick
python3 - "\$DEVNODE" "\$DUR" <<'PY'
import ctypes, os, struct, sys, threading, time, subprocess
path, dur = sys.argv[1], int(sys.argv[2])
fd = os.open(path, os.O_RDWR)
libc = ctypes.CDLL("libc.so.6", use_errno=True)

class TimeVal(ctypes.Structure):
    _fields_ = [("tv_sec", ctypes.c_long), ("tv_usec", ctypes.c_long)]
class Trigger(ctypes.Structure):
    _fields_ = [("button", ctypes.c_uint16), ("interval", ctypes.c_uint16)]
class Rumble(ctypes.Structure):
    _fields_ = [("weak_magnitude", ctypes.c_uint16), ("strong_magnitude", ctypes.c_uint16)]
class EffectUnion(ctypes.Union):
    _fields_ = [("rummy", Rumble)]
class FFEffect(ctypes.Structure):
    _fields_ = [("type", ctypes.c_uint16), ("id", ctypes.c_int16),
                ("direction", ctypes.c_uint16), ("trigger", Trigger),
                ("u", EffectUnion), ("replay", TimeVal),
                ("samples", ctypes.c_uint16), ("pad", ctypes.c_uint16)]

# FF_RUMBLE = 0x50; EVIOCSFF = _IOW('E', 0x80, struct ff_effect) -> 0x40284580
EVIOCSFF = 0x40284580
EVIOCRMFF = 0x80014581
eff = FFEffect()
eff.type = 0x50
eff.id = -1
eff.u.rummy.strong_magnitude = 0xffff
eff.u.rummy.weak_magnitude = 0x4000
eff.replay.tv_sec = dur // 1000
eff.replay.tv_usec = (dur % 1000) * 1000
buf = ctypes.create_string_buffer(ctypes.sizeof(eff))
ctypes.memmove(buf, ctypes.byref(eff), ctypes.sizeof(eff))
if libc.ioctl(fd, EVIOCSFF, buf) != 0:
    print("  upload failed:", os.strerror(ctypes.get_errno()))
    raise SystemExit(1)
eff_id = struct.unpack_from("h", buf.raw, 2)[0]
print("  effect uploaded, id=%d, %d ms" % (eff_id, dur))

def sample(stop, out):
    while time.monotonic() < stop:
        try:
            txt = subprocess.run(["grep", "-A1", "gpiochip0:", "/sys/kernel/debug/gpio"],
                                 capture_output=True, text=True).stdout
        except Exception:
            txt = ""
        for line in txt.splitlines():
            if "|rumble" in line:
                out.append(line.strip())
        time.sleep(0.05)

seen = []
t = threading.Thread(target=sample, args=(time.monotonic() + dur/1000.0 + 0.3, seen))
t.start()
os.write(fd, struct.pack("lllH", int(time.time()), 0, 0, 0))  # placeholder, replaced below
t.join()
os.close(fd)
PY
EOS
echo "=== (see below for the rewritten runner) ==="
