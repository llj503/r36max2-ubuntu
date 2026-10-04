#!/bin/bash
# Non-interactive password SSH into the Ubuntu-on-R36Max2 device.
# Usage: UBPW=ubuntu bash E:/ubuntu/build/uscp.sh 'remote command'
AP="C:\\Users\\llj\\AppData\\Local\\Temp\\sshap\\AskPass.exe"
HOST="${UBHOST:-ubuntu@192.168.31.103}"
SSH_ASKPASS="$AP" SSH_ASKPASS_REQUIRE=force SSHPW="${UBPW:-ubuntu}" \
/c/Windows/System32/OpenSSH/ssh.exe -o ConnectTimeout=15 -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=NUL -o PreferredAuthentications=password -o PubkeyAuthentication=no \
  -o ServerAliveInterval=15 "$HOST" "$@" 2>&1 | tr -d '\r'
