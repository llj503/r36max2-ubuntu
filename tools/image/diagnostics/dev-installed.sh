#!/bin/bash
# dev-installed.sh - what did I apt-install on the device beyond the image?
# history.log starts with the base debootstrap reinstalls, so look at the tail.
set -uo pipefail
DEV=${DEV:-192.168.31.209}
sshpass -p ubuntu ssh -o ConnectTimeout=15 root@$DEV \
  'echo "=== last 12 command lines ==="; grep -h "^Commandline:" /var/log/apt/history.log | tail -12;
   echo; echo "=== packages installed by those (Install: stanzas, last 300 lines) ===";
   tac /var/log/apt/history.log | awk "/^Install:/{print; c++} c>0 && /^$/{exit}" | tr "," "\n" | sed "s/([^)]*)//g;s/^Install: //;s/^ *//" | awk "{print \$1}" | sort -u | head -80' </dev/null 2>/dev/null
