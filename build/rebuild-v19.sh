#!/bin/bash
# rebuild-v19.sh - apply + pack in one go, logging to the Windows side so the
# output survives WSL being reclaimed.
set -uo pipefail
mkdir -p /mnt/e/ubuntu/logs
{
  bash /mnt/e/ubuntu/build/apply-v19.sh 2>&1 | tail -30
  echo "########## PACK ##########"
  V=v19 bash /mnt/e/ubuntu/build/pack-v10.sh 2>&1 | tail -18
} 2>&1 | tee /mnt/e/ubuntu/logs/rebuild-v19.log
