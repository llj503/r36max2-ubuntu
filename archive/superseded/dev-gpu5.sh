#!/bin/bash
set -uo pipefail
K=/root/r36/linux-6.12.79
DEV=192.168.31.210
PW=ubuntu
S() { sshpass -p "$PW" ssh -o ConnectTimeout=10 root@$DEV "$@" </dev/null 2>/dev/null; }

echo "=== where is the mfd driver + the gpu opp table ==="
ls "$K/drivers/mfd" | grep -i rk8
grep -rln 'gpu_opp_table' "$K/arch/arm64/boot/dts/rockchip/" | head -5
echo "--- the table itself ---"
grep -rn -A22 'gpu_opp_table:' "$K/arch/arm64/boot/dts/rockchip/rk3326.dtsi" 2>/dev/null | head -30
echo "--- what the compiled dtb has for the gpu ---"
dtc -I dtb -O dts "$K/arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dtb" 2>/dev/null > /tmp/g.dts
awk '/gpu-opp-table|opp-table \{/,/^\t\};/' /tmp/g.dts | head -30
awk '/gpu@ff400000 \{/,/^\t\};/' /tmp/g.dts | grep -E 'operating|mali-supply|clocks|status|power-domain'

echo "=== live regulator constraints ==="
S 'cat /sys/kernel/debug/regulator/regulator_summary 2>/dev/null | head -4
   cat /sys/kernel/debug/regulator/regulator_summary 2>/dev/null | grep -iE "vdd_logic|vdd_arm" | head -6'
echo "=== the exact failing request context ==="
S 'dmesg | grep -iE "vdd_logic|rk8xx|regulator" | tail -8'
