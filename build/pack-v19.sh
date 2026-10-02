#!/bin/bash
# pack-v19.sh - thin wrapper so the version is never typed inline (WSL eats
# $vars in inline commands) and the log lands on the Windows side where it
# survives WSL being reclaimed while idle.
set -uo pipefail
export V=v19
mkdir -p /mnt/e/ubuntu/logs
bash /mnt/e/ubuntu/build/pack-v10.sh 2>&1 | tee /mnt/e/ubuntu/logs/pack-v19.log | tail -40
echo "pack exit=${PIPESTATUS[0]}"
