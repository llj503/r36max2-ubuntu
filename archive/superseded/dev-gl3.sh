#!/bin/bash
# dev-gl3.sh - compile and run the GLES2/GBM demo on the device, report fps +
# shader read-back, and pull the rendered frame out as a PNG.
set -uo pipefail
DEV=${DEV:-192.168.31.209}
S() { sshpass -p ubuntu ssh -o ConnectTimeout=15 root@$DEV "$@" </dev/null 2>/dev/null; }

sshpass -p ubuntu scp -q /mnt/e/ubuntu/packages/gpu-demos/r36-gles2-demo.c "$DEV:/root/r36-gles2-demo.c"
echo "=== build ==="
S 'cd /root && gcc -O2 -o r36-gles2-demo r36-gles2-demo.c $(pkg-config --cflags --libs gbm egl glesv2 libdrm) -ldrm 2>&1 | head -20 && ls -l r36-gles2-demo'

echo "=== run (6s render, hold the last frame 14s so you can see it on the panel) ==="
S 'cd /root; R36_HOLD=14 ./r36-gles2-demo /dev/dri/card0 6 > /tmp/gl.log 2>&1 & echo "  started, pid $!"'
sleep 9
echo "  --- log so far ---"
S 'sed -n "1,30p" /tmp/gl.log | sed "s/^/  /"'
sleep 12
echo "  --- final log ---"
S 'sed -n "1,40p" /tmp/gl.log | sed "s/^/  /"'
echo "=== pull the rendered frame ==="
sshpass -p ubuntu scp -q "$DEV:/tmp/gl-frame.ppm" /tmp/gl-frame.ppm 2>/dev/null
if [ -s /tmp/gl-frame.ppm ]; then
  HDR=$(head -c 15 /tmp/gl-frame.ppm | tr '\n' ' ')
  echo "  ppm header: [$HDR] size=$(stat -c %s /tmp/gl-frame.ppm)"
  python3 - <<'PY'
data = open('/tmp/gl-frame.ppm','rb').read()
assert data[:2] == b'P6', data[:2]
i, toks = 2, []
while len(toks) < 3:
    while i < len(data) and data[i:i+1].isspace(): i += 1
    j = i
    while j < len(data) and not data[j:j+1].isspace(): j += 1
    toks.append(int(data[i:j])); i = j
w, h, mx = toks
raw = data[i+1:]          # skip the single whitespace after the max-value token
open('/tmp/gl-frame.raw','wb').write(raw)
print(f"  parsed {w}x{h} max={mx} raw={len(raw)} bytes (expect {w*h*3})")
PY
  python3 /mnt/e/ubuntu/tools/capture/raw2png.py /tmp/gl-frame.raw /mnt/e/ubuntu/documentation/PER_DEVICE_DOCUMENTATION/r36max2/images/gl-frame.png 256 192 24 768 2>&1 | tail -2
  ls -la /mnt/e/ubuntu/documentation/PER_DEVICE_DOCUMENTATION/r36max2/images/gl-frame.png
fi
echo "=== gpu state during/after ==="
S 'cat /sys/class/devfreq/ff400000.gpu/cur_freq 2>/dev/null | sed "s/^/  gpu now: /"; dmesg | tail -4 | sed "s/^/  /"'
echo "=== console back on the panel? (fb0 grab) ==="
DEV=$DEV bash /mnt/e/ubuntu/tools/capture/shot.sh 2>&1 | tail -3
