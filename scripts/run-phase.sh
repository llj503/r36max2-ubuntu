#!/bin/bash
# run-phase.sh - run a smoke phase on the board with the parameters set INSIDE WSL.
#
# Why this wrapper exists (measured 2026-10-03 20:19): the call
#     TREE=es PHASE=B WAIT=30 wsl.exe -- bash /mnt/e/ubuntu/tools/emulationstation/runtime/k72-esrn-autorun.sh run
# arrived as `phase=A wait=25` - the assignments on the Windows side never crossed into
# the WSL process, and k72-esrn-autorun.sh then used its own defaults.  It had looked like
# the channel worked all evening only because the values I passed (TREE=es, PHASE=A) were
# identical to those defaults.  Arguments and env through wsl.exe are not trustworthy here;
# set the variables in a file that WSL itself executes.
#
#   bash scripts/run-phase.sh B 30          # phase B, 30s window, batocera tree
#   bash scripts/run-phase.sh A 25 esrn     # same for the other tree
set -uo pipefail
PH=${1:-B}
WT=${2:-30}
TR=${3:-es}
cd /mnt/e/ubuntu || exit 1
echo "  run-phase: PHASE=$PH WAIT=$WT TREE=$TR  (set inside WSL, not through wsl.exe)"
case "$PH" in A|B) ;; *) echo "  !! phase must be A or B"; exit 2 ;; esac
export PHASE="$PH"
export WAIT="$WT"
export TREE="$TR"
export DIR="/root/$TR"
export BIN="/root/$TR/build/es-app/emulationstation"
export LOG="/tmp/es-$TR-build.log"
exec bash tools/emulationstation/runtime/k72-esrn-autorun.sh run
