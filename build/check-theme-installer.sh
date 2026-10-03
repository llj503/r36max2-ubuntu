#!/bin/bash
# check-theme-installer.sh - syntax-check k72-es-theme-install.sh the way the other
# rig scripts get checked: the outer bash, the dash body that actually runs on the board,
# and every python block embedded in it.
#
# Written as a file on purpose.  The first attempt was an inline
# `wsl.exe -- bash -c '... awk "/^EOS\$/" ...'`, and the \$ reached awk as a literal
# dollar, so the extractor produced an EMPTY file and `sh -n <empty>` cheerfully printed
# OK.  An empty input passing a syntax check is a lie; this script refuses to grade
# anything it could not extract.
set -uo pipefail
S=${1:-/mnt/e/ubuntu/build/k72-es-theme-install.sh}
CH=$(command -v python3 || echo /usr/bin/python3)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
rc=0

echo "=== file under test: $S ==="
[ -f "$S" ] || { echo "  !! not found"; exit 1; }
echo "  lines: $(wc -l < "$S")"

# 1) the whole script as bash
bash -n "$S" && echo "  [1] outer bash syntax OK" || { echo "  [1] !! bash syntax error"; rc=1; }

# 2) the remote body (everything between the ssh heredoc markers), as POSIX sh
awk 'f { if ($0 == "EOS") { f = 0; next } print } /^timeout 300 sshpass/ { f = 1 }' "$S" > "$tmp/body.sh"
n=$(wc -l < "$tmp/body.sh")
if [ "$n" -lt 20 ]; then
  echo "  [2] !! extracted only $n line(s) - refusing to call that a pass"
  rc=1
else
  echo "  [2] remote body: $n lines"
  sh -n "$tmp/body.sh" && echo "      POSIX sh syntax OK" || { echo "      !! sh syntax error"; rc=1; }
fi

# 3) each embedded python block
i=0
awk -v out="$tmp" '
  /^ *python3 - / { p = 1; n++; f = out "/blk" n ".py"; next }
  /^PY$/          { p = 0; next }
  p               { print > f }
' "$S"
for b in "$tmp"/blk*.py; do
  [ -f "$b" ] || continue
  i=$((i + 1))
  l=$(wc -l < "$b")
  if [ "$l" -lt 3 ]; then
    echo "  [3] !! $(basename "$b") has only $l line(s), not a real extraction"
    rc=1
    continue
  fi
  if "$CH" -m py_compile "$b" 2>"$tmp/err"; then
    echo "  [3] $(basename "$b") ($l lines) compiles OK"
  else
    echo "  [3] !! $(basename "$b") does not compile:"
    sed 's/^/       /' "$tmp/err"
    rc=1
  fi
done
[ "$i" = 0 ] && { echo "  [3] !! no python blocks found at all"; rc=1; }

echo "=== overall rc=$rc ==="
exit "$rc"
