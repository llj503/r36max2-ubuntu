#!/bin/bash
# dev-absinfo.sh - read the declared axis ranges (for calibration) and replay a
# clearly identifiable audio pattern.
set -uo pipefail
DEV=root@192.168.31.210
PW=ubuntu
S() { sshpass -p "$PW" ssh -o ConnectTimeout=10 "$DEV" "$@" </dev/null; }

cat > /tmp/absinfo.py <<'PY'
import fcntl, os, struct
EVIOCGABS = lambda code: 0xc0284540 | (2 << 30) | (0x45 << 8) | code
# struct input_absinfo: i32 value,min,max,fuzz,flat; i32(=long padding) resolution
for dev in ("/dev/input/event2",):
    fd = os.open(dev, os.O_RDONLY)
    print(dev)
    for name, code in (("ABS_X",0x00),("ABS_Y",0x01),("ABS_Z",0x02),("ABS_RX",0x03),
                       ("ABS_RY",0x04),("ABS_RZ",0x05),("ABS_HAT0X",0x10),("ABS_HAT0Y",0x11)):
        try:
            buf = struct.pack("6i", *([0]*6))
            out = fcntl.ioctl(fd, EVIOCGABS(code), buf)
            v, mn, mx, fz, fl, res = struct.unpack("6i", out)
            print("  %-9s min=%-7s max=%-7s value=%-7s fuzz=%s flat=%s res=%s" % (name, mn, mx, v, fz, fl, res))
        except OSError as e:
            pass
    os.close(fd)
PY
sshpass -p "$PW" scp -q /tmp/absinfo.py "$DEV:/tmp/absinfo.py"
echo "=== declared axis ranges ==="
S 'python3 /tmp/absinfo.py'

echo "=== apt finished? packages installed ==="
S 'pgrep -x apt-get >/dev/null && echo "apt still running" || echo "apt done"; tail -2 /root/setup.log; dpkg -l 2>/dev/null | awk "/^ii/{n++}END{print \"packages: \" n}"'

echo "=== audio: 3 x (1s tone + 0.8s silence) at 880 Hz ==="
S "amixer -c 0 contents | grep -A3 'Playback Mux' | tail -1
   amixer -c 0 sget 'Master' 2>/dev/null | tail -2
   for i in 1 2 3; do timeout 1 speaker-test -D plughw:0,0 -c 2 -t sine -f 880 -l 1 >/dev/null 2>&1; sleep 0.8; done
   echo '3 beeps played'"
