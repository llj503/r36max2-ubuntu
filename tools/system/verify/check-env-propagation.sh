#!/bin/bash
# check-env-propagation.sh - does `VAR=x wsl.exe -- bash f.sh` actually deliver VAR into
# WSL?  It looked like it worked all evening because every value I passed happened to
# equal the script's own default (TREE=es, PHASE=A) - a coincidence that hides a broken
# call convention.  This tests with values that differ from any default.
set -u
echo "=== Git Bash side ==="
echo "  MYVAR is set here? [${MYVAR:-<unset>}]"
echo "=== via wsl.exe with the var on the windows command line ==="
MSYS_NO_PATHCONV=1 MYVAR=fromWindows wsl.exe -- bash -c 'echo "  inside WSL: MYVAR=[${MYVAR:-<EMPTY>}]"'
echo "=== via env(1) INSIDE the wsl command line (the pattern that must be used) ==="
MSYS_NO_PATHCONV=1 wsl.exe -- env MYVAR=viaEnv bash -c 'echo "  inside WSL: MYVAR=[${MYVAR:-<EMPTY>}]"'
echo "=== via a literal assignment in the -c string ==="
MSYS_NO_PATHCONV=1 wsl.exe -- bash -c 'MYVAR=literal; echo "  inside WSL: MYVAR=[$MYVAR]"'
