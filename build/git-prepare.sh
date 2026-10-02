#!/bin/bash
# git-prepare.sh - download the GPL-2.0 text, init the repo, stage everything
# the .gitignore allows, then audit what actually got staged (size + secrets).
set -uo pipefail
cd /e/ubuntu || exit 1

if [ ! -f LICENSE ]; then
  curl -sSL --max-time 60 -o LICENSE https://www.gnu.org/licenses/old-licenses/gpl-2.0.txt \
    && echo "LICENSE: $(wc -l < LICENSE) lines, $(wc -c < LICENSE) bytes" \
    || echo "LICENSE download FAILED (copy it in manually)"
fi

[ -d .git ] || git init -b main

git add -A 2>&1 | tail -5
echo "=== staged file count: $(git diff --cached --name-only | wc -l)"
echo "=== staged, largest first (top 12)"
git diff --cached --name-only -z | xargs -0 -I{} du -k "{}" 2>/dev/null | sort -rn | head -12
echo "=== anything over 5 MB staged? (should be empty)"
git diff --cached --name-only -z | xargs -0 -I{} sh -c 'test $(du -m "{}" | cut -f1) -gt 5 && echo "  BIG: {}"' 2>/dev/null | head
echo "=== secret check (must all be 0) ==="
for pat in wifi-cred wpa_supplicant- '\.img$' '\.img\.xz$' '\.iso$' 'rocknix/' 'build/wifi/' 'aic-src' '\.ko$' '\.dtb$'; do
  n=$(git diff --cached --name-only | grep -cE "$pat")
  echo "  $pat -> $n"
done
echo "=== top-level of what will be committed"
git diff --cached --name-only | awk -F/ '{print $1"/"$2}' | sort -u | head -30
