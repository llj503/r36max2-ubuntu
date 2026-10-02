#!/bin/bash
# dev-gpu2.sh - which rail does mali-supply point at, and can it produce 950 mV?
set -uo pipefail
D=/root/r36/linux-6.12.79/arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dts
echo "=== &gpu node ==="
awk '/^&gpu \{/,/^\};/' "$D"
echo "=== gpu_opp_table (our dts or the included dtsi) ==="
grep -rn -A26 'gpu_opp_table:' "$D" /root/r36/linux-6.12.79/arch/arm64/boot/dts/rockchip/rk3326*.dtsi 2>/dev/null | head -40
echo "=== rk817 regulator block (which DCDC is vdd_logic, what ranges) ==="
awk '/regulators \{/,/^\t\t\};/' "$D" | head -70
echo "=== fixed regulators that could be mistaken for the gpu rail ==="
grep -n -B2 -A8 'vcc_core\|vdd_gpu\|vcc3v3_gpu\|vcc_logic' "$D" | head -40
echo "=== mainline rk808 mfd: DCDC1 voltage range/step ==="
grep -n -A12 'rk817_regulator_info\|RK817_ID_DC1\|DCDC1' /root/r36/linux-6.12.79/drivers/mfd/rk808.c 2>/dev/null | head -30
ls /root/r36/linux-6.12.79/drivers/mfd/ | grep -i rk8
