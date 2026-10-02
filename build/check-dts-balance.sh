#!/bin/bash
set -uo pipefail
D=/root/r36/linux-6.12.79/arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dts
echo "=== last 26 lines with numbers ==="
tail -26 "$D" | cat -n
echo "=== brace balance of the file as written ==="
python3 - "$D" <<'PY'
import sys, re
src = open(sys.argv[1]).read()
# strip C-style comments the way cpp would
noc = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
noc = re.sub(r'//[^\n]*', '', noc)
print("  { =", noc.count("{"), " } =", noc.count("}"), " balanced:", noc.count("{") == noc.count("}"))
raw_o, raw_c = src.count("{"), src.count("}")
print("  raw { =", raw_o, " raw } =", raw_c)
# show the tail of the comment-stripped source
t = noc.rstrip()
print("  --- last 200 chars after stripping comments ---")
print("  " + t[-200:].replace("\n", "\n  "))
PY
echo "=== the unbalanced comment: find /* ... */ pairs near the end ==="
grep -n '/\*\|\*/' "$D" | tail -12
