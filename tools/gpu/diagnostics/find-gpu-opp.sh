#!/bin/bash
set -uo pipefail
K=/root/r36/linux-6.12.79
R=$K/arch/arm64/boot/dts/rockchip
echo "=== files mentioning gpu_opp_table (excluding build temp) ==="
grep -rln 'gpu_opp_table' "$R" --include='*.dts' --include='*.dtsi' | head
echo "=== the table in rk3326.dtsi ==="
sed -n '/gpu_opp_table:/,/^};/p' "$R/rk3326.dtsi" | head -40
echo "=== gpu node in rk3326.dtsi ==="
sed -n '/gpu: gpu@ff400000/,/^\t};/p' "$R/rk3326.dtsi" | grep -E 'operating|mali|clocks|power-domain|status|assigned'
echo "=== every consumer of vdd_logic on this board ==="
grep -rn 'vdd_logic' "$R"/rk3326*.dts "$R"/rk3326.dtsi 2>/dev/null | head -12
echo "=== our board dts: any opp override already? ==="
grep -n 'opp' "$R/rk3326-xifan-r36max2.dts" | head
