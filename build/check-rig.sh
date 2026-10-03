#!/bin/bash
# check-rig.sh - syntax-check a k72-*/r36-* rig script properly: the outer bash, the shell
# body that is actually fed to the board, and every python block inside it.
#
# This exists because a hand-rolled `awk "/^EOS\\$/"` inside `wsl.exe -- bash -c '...'`
# extracted NOTHING (the escaping made the pattern require a literal "$"), and
# `sh -n <empty file>` then reported "syntax OK".  An empty extraction passing a check is
# worse than a failure, so this script treats "could not extract" as a hard error and
# prints how many lines it found at every step.
#
#   bash build/check-rig.sh build/k72-es-sticknav.sh
#   bash build/check-rig.sh build/k72-es-theme-install.sh
#
# The remote body is located by the heredoc markers, not by the ssh line, so it works for
# `<<'EOS'`, `<<EOS` and `<<'EOW'` alike.
set -uo pipefail
S=${1:-}
[ -n "$S" ] && [ -f "$S" ] || { echo "usage: bash build/check-rig.sh <script>"; exit 2; }
PY=$(command -v python3 || echo /usr/bin/python3)
SH=${SH:-sh}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
rc=0
fail() { echo "  !! $*"; rc=1; }

echo "=== $S ==="
echo "  lines: $(wc -l < "$S")"

# 1) outer script as bash
bash -n "$S" && echo "  [1] outer bash: OK" || fail "[1] outer bash syntax error"

# 2) every heredoc body (any ALL-CAPS tag), checked as POSIX sh
tags=$(grep -oE "<<-?'?[A-Z]{2,}'?" "$S" | tr -d "<'-" | sort -u)
[ -n "$tags" ] || echo "  (no uppercase heredoc tags found)"
for t in $tags; do
  # index() rather than a regex: the opener may be <<EOS, <<'EOS', <<-EOS or <<'EOW', and
  # a $-anchored pattern silently misses the trailing quote - which is how an EMPTY
  # extraction got "checked" and reported OK once already
  awk -v T="$t" '
    !inb && index($0, "<<") > 0 && index($0, T) > 0 { inb = 1; next }
    inb && $0 == T { inb = 0; next }
    inb { print }
  ' "$S" > "$tmp/body-$t.sh"
  n=$(wc -l < "$tmp/body-$t.sh")
  if [ "$n" -lt 5 ]; then
    echo "  [2] heredoc <<$t : extracted only $n line(s) - SKIPPED, not claimed as a pass"
    continue
  fi
  # a PY tag means the body IS python: checking python as sh is the checker's bug, not
  # the rig's (it "failed" two perfectly good scripts that way)
  case "$t" in
    PY)
      if "$PY" -m py_compile "$tmp/body-$t.sh" 2>"$tmp/err-$t"; then
        echo "  [2] heredoc <<$t : $n lines, python compiles OK"
      else
        fail "[2] heredoc <<$t ($n lines): $(head -2 "$tmp/err-$t")"
      fi
      continue
      ;;
  esac
  if $SH -n "$tmp/body-$t.sh" 2>"$tmp/err-$t"; then
    echo "  [2] heredoc <<$t : $n lines, POSIX sh syntax OK"
  else
    fail "[2] heredoc <<$t ($n lines): $(head -2 "$tmp/err-$t")"
  fi
  # 3) python blocks inside that body
  k=0
  awk -v out="$tmp" -v tag="$t" '
    /^[[:space:]]*(python3?|PYBIN)([[:space:]]|$).*<<.?PY/ { k++; f = out "/py-" tag "-" k ".py"; inb = 1; next }
    inb && /^PY$/ { inb = 0; next }
    inb { print > f }
  ' "$tmp/body-$t.sh"
  for p in "$tmp"/py-$t-*.py; do
    [ -f "$p" ] || continue
    l=$(wc -l < "$p")
    if [ "$l" -lt 3 ]; then fail "[3] $(basename "$p"): only $l line(s) extracted"; continue; fi
    if "$PY" -m py_compile "$p" 2>"$tmp/pyerr"; then
      echo "  [3] python in <<$t: $(basename "$p") $l lines OK"
    else
      fail "[3] $(basename "$p") does not compile: $(head -2 "$tmp/pyerr" | tr '\n' ' ')"
    fi
  done
done

echo "=== overall: $([ $rc = 0 ] && echo PASS || echo FAIL) ==="
exit $rc
