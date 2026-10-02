#!/bin/bash
# Give WSL passwordless SSH to the device: generate a key there and push it via
# the Windows askpass helper. Afterwards all device work runs inside WSL (scp,
# rsync, python3, long jobs) without the password dance.
set -uo pipefail
AP="C:\\Users\\llj\\AppData\\Local\\Temp\\sshap\\AskPass.exe"
HOST=root@192.168.31.210
DEV_IP=192.168.31.210

echo "=== 1. key in WSL ==="
wsl.exe -d Ubuntu -- bash -c '
  [ -f /root/.ssh/id_ed25519 ] || ssh-keygen -t ed25519 -N "" -C "wsl-r36max2" -f /root/.ssh/id_ed25519 -q
  echo "pubkey: $(cut -d" " -f1,2 /root/.ssh/id_ed25519.pub)"
  grep -q r36max2 /root/.ssh/config 2>/dev/null || printf "Host %s\n  User root\n  StrictHostKeyChecking no\n  UserKnownHostsFile /dev/null\n" "$1" >> /root/.ssh/config
' "$DEV_IP"

PUB=$(wsl.exe -d Ubuntu -- bash -c 'cat /root/.ssh/id_ed25519.pub' | tr -d '\r')
echo "=== 2. push it through the Windows ssh ==="
SSH_ASKPASS="$AP" SSH_ASKPASS_REQUIRE=force SSHPW=ubuntu \
  /c/Windows/System32/OpenSSH/ssh.exe -o ConnectTimeout=15 -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=NUL -o PreferredAuthentications=password -o PubkeyAuthentication=no \
  "$HOST" "mkdir -p /root/.ssh && chmod 700 /root/.ssh && grep -qF 'wsl-r36max2' /root/.ssh/authorized_keys 2>/dev/null || echo '$PUB' >> /root/.ssh/authorized_keys; chmod 600 /root/.ssh/authorized_keys; wc -l /root/.ssh/authorized_keys" 2>&1 | tail -3

echo "=== 3. test from WSL (BatchMode, no password) ==="
wsl.exe -d Ubuntu -- bash -c "ssh -o BatchMode=yes -o ConnectTimeout=10 $DEV_IP 'echo WSL-SSH-OK; hostname; uname -r; python3 -V; df -h / | tail -1'" 2>&1 | tail -8
echo "=== 4. scp sanity ==="
wsl.exe -d Ubuntu -- bash -c "echo hello-from-wsl > /tmp/t.txt && scp -q -o BatchMode=yes /tmp/t.txt $DEV_IP:/tmp/ && ssh -o BatchMode=yes $DEV_IP 'cat /tmp/t.txt'" 2>&1 | tail -3
