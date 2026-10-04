#!/bin/bash
set -uo pipefail
D=/root/r36/linux-6.12.79/arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dts
echo "lines in dts: $(wc -l < "$D")"
echo "=== 318-368 (spk_amp + sound card) ==="
sed -n '318,368p' "$D"
echo "=== 744-762 (&i2s1_2ch) ==="
sed -n '744,762p' "$D"
echo "=== 966-986 (spk_amp_enable pin group) ==="
sed -n '966,986p' "$D"
echo "=== 912-928 (hp_det pin group) ==="
sed -n '912,928p' "$D"
echo "=== 520-545 (rk817 pmic clocks) ==="
sed -n '520,545p' "$D"
