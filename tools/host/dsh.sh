#!/bin/bash
# From now on the device is driven from inside WSL with sshpass: ssh, scp, rsync
# and python3 all in one place. This also captures the panel (framebuffer -> PNG).
set -uo pipefail
DEV=root@192.168.31.210
PW=ubuntu

echo "=== 0. clean the mangled ssh config ==="
cat > /root/.ssh/config <<'EOF'
Host 192.168.31.210 r36max2
    User root
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    loglevel ERROR
EOF
rm -f /root/.ssh/id_ed25519.pub 2>/dev/null
echo "config rewritten"

S() { sshpass -p "$PW" ssh -o ConnectTimeout=15 "$DEV" "$@"; }
echo "=== 1. ssh through WSL ==="
S 'echo WSL-SSH-OK; hostname; uname -r; python3 -V 2>&1; df -h / | tail -1; systemctl is-active r36-wpa@wlan0 systemd-udevd ssh'
echo "=== 2. scp ==="
echo hello-from-wsl > /tmp/t.txt
sshpass -p "$PW" scp -q /tmp/t.txt "$DEV:/tmp/" && S 'cat /tmp/t.txt'
echo "=== 3. apt job still running? ==="
S 'tail -2 /root/setup.log; pgrep -a apt | head -2; dpkg -l | grep -c "^i  " || true'
echo "=== 4. framebuffer geometry ==="
S 'printf "vs=%s bpp=%s ll=%s\n" "$(cat /sys/class/graphics/fb0/virtual_size)" "$(cat /sys/class/graphics/fb0/bits_per_pixel)" "$(cat /sys/class/graphics/fb0/line_length)"; ls -l /dev/fb0'
