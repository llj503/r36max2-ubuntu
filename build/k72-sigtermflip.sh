#!/bin/bash
# k72-sigtermflip.sh - push and run the SIGTERM variant of the wedge experiment.
# If it reproduces, the panel stays frozen afterwards and needs a reboot; the run
# stops at the first reproduction and says so.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
SRC=/mnt/e/ubuntu/build

sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV 'cat > /usr/local/bin/r36-sigtermflip.sh' \
  < "$SRC/r36-sigtermflip-device.sh"
timeout 900 sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV \
  'chmod 755 /usr/local/bin/r36-sigtermflip.sh; sh /usr/local/bin/r36-sigtermflip.sh' 2>&1
rc=$?
echo "=== sigterm-flip rc=$rc (1 = reproduced -> panel frozen, ask before reboot; 0 = not reproduced) ==="
exit $rc
