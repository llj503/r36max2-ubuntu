#!/bin/bash
set -uo pipefail
D=/root/r36/linux-6.12.79/arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dts
K=/root/r36/linux-6.12.79
echo "=== lines 975-1000 with invisible characters ==="
sed -n '975,1000p' "$D" | cat -A | sed 's/\$$/<EOL>/'
echo
echo "=== preprocess with cpp and see what dtc actually receives ==="
cd "$K"
cpp -nostdinc -I scripts/dtc/libfdt -I include -I arch/arm64/boot/dts -undef -D__DTS__ -x assembler-with-cpp "$D" 2>/dev/null > /tmp/pp.dts
echo "  preprocessed lines: $(wc -l < /tmp/pp.dts)"
grep -n 'r36_gpu_opp' /tmp/pp.dts | head -3
N=$(grep -n 'r36_gpu_opp:' /tmp/pp.dts | head -1 | cut -d: -f1)
echo "  --- context around line $N of the preprocessed file ---"
sed -n "$((N-6)),$((N+3))p" /tmp/pp.dts | cat -A
echo "  --- try dtc on it directly ---"
dtc -I dts -O dtb -o /tmp/test.dtb /tmp/pp.dts 2>&1 | head -8
