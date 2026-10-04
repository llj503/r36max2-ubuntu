#!/bin/bash
# git-secretscan.sh - make sure nothing that looks like a credential is in the
# staged tree.  Prints FILENAMES only, never the matched content.
set -uo pipefail
cd /e/ubuntu || exit 1
CRED=/e/ubuntu/build/wifi-cred.txt
SSID=$(grep '^Name=' "$CRED" | cut -d= -f2- | tr -d '\r')
PSK=$(grep '^Passphrase=' "$CRED" | cut -d= -f2- | tr -d '\r')

hits=0
scan() {   # $1 = label, $2 = literal string to look for
  [ -n "$2" ] || return 0
  local found
  # the scanner holds the very patterns we look for - never scan it
  found=$(git diff --cached --name-only -z | xargs -0 grep -lI -F -- "$2" 2>/dev/null | grep -v '^tools/system/verify/git-secretscan.sh$')
  if [ -n "$found" ]; then
    echo "  $1 -> LEAK in:"; echo "$found" | sed 's/^/      /'
    hits=$((hits + 1))
  else
    echo "  $1 -> clean"
  fi
}
echo "=== scanning $(git diff --cached --name-only | wc -l) staged files ==="
scan "wifi passphrase" "$PSK"
scan "wifi SSID" "$SSID"
scan "generic psk= literal" 'psk="'
scan "sshpass -p <pw>" 'sshpass -p ubuntu'
scan "private key block" 'BEGIN OPENSSH PRIVATE KEY'
scan "token-ish" 'ghp_'
echo "=== done, $hits leak group(s) ==="
