#!/bin/bash
# Push r36-fbshot.py to the device, run it, and pull the PNG back (binary-safe:
# no tr -d '\r' on the download path).
set -uo pipefail
AP="C:\\Users\\llj\\AppData\\Local\\Temp\\sshap\\AskPass.exe"
HOST="${DH:-root@192.168.31.210}"
PW="${DPW:-ubuntu}"
SRC=/mnt/e/ubuntu/build/r36-fbshot.py
[ -f "$SRC" ] || SRC="E:/ubuntu/build/r36-fbshot.py"
OUT_DIR=/e/ubuntu/shots
mkdir -p "$OUT_DIR"
TS=$(date +%H%M%S)

run() { SSH_ASKPASS="$AP" SSH_ASKPASS_REQUIRE=force SSHPW="$PW" \
  /c/Windows/System32/OpenSSH/ssh.exe -o ConnectTimeout=15 -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=NUL -o PreferredAuthentications=password -o PubkeyAuthentication=no "$HOST" "$@"; }

B64=$(base64 -w0 "$SRC" 2>/dev/null || python3 - <<'PY' 2>/dev/null
import base64;print(base64.b64encode(open('/mnt/e/ubuntu/build/r36-fbshot.py','rb').read()).decode())
PY
)
echo "push: ${#B64} b64 bytes"
run "echo $B64 | base64 -d > /usr/local/bin/r36-fbshot && chmod 755 /usr/local/bin/r36-fbshot && python3 -c 'import py_compile,sys; py_compile.compile(\"/usr/local/bin/r36-fbshot\"); print(\"compiles\")'"
echo "--- run it ---"
run "time python3 /usr/local/bin/r36-fbshot /tmp/screen.png; ls -la /tmp/screen.png"
echo "--- pull ---"
SSH_ASKPASS="$AP" SSH_ASKPASS_REQUIRE=force SSHPW="$PW" \
  /c/Windows/System32/OpenSSH/ssh.exe -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL \
  -o PreferredAuthentications=password -o PubkeyAuthentication=no "$HOST" \
  "cat /tmp/screen.png" > "$OUT_DIR/screen-$TS.png"
ls -la "$OUT_DIR/screen-$TS.png"
file "$OUT_DIR/screen-$TS.png" 2>/dev/null || head -c 8 "$OUT_DIR/screen-$TS.png" | od -An -tx1
echo "SAVED=$OUT_DIR/screen-$TS.png"
