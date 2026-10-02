#!/bin/bash
# dev-gpu4.sh - regulator constraints + the driver's idea of DCDC1's range/modes.
set -uo pipefail
K=/root/r36/linux-6.12.79
DEV=192.168.31.210
PW=ubuntu
S() { sshpass -p "$PW" ssh -o ConnectTimeout=10 root@$DEV "$@" </dev/null 2>/dev/null; }

echo "=== regulator summary (vdd_logic line + its consumers) ==="
S 'mount -t debugfs none /sys/kernel/debug 2>/dev/null
   grep -nE "^\s*\S+\s+\d+\s+\d" /sys/kernel/debug/regulator/regulator_summary | head -3
   grep -E "vdd_logic|vdd_arm" /sys/kernel/debug/regulator/regulator_summary | head -8
   echo "--- full dump around vdd_logic ---"
   grep -B2 -A6 "vdd_logic" /sys/kernel/debug/regulator/regulator_summary | head -24'

echo "=== driver: RK817 DCDC1 definition, ranges, and mode constants ==="
grep -nE "RK817|DCDC1|linear_range|\.min_uV|\.max_uV|n_voltages|volt_table|MODE_|list_modes|change_voltage|of_get_regulator_init_mode" "$K/drivers/regulator/rk808-regulator.c" | head -30
echo "--- mode enum in the mfd header ---"
grep -rnE "RK8XX_MODE_[A-Z]+\s*=|MODE_[A-Z]+ = " "$K/include/linux/mfd/rk808.h" | head -10
echo "--- how the mfd driver registers init mode ---"
grep -nE "initial_mode|of_property_read.*mode|regulator_init_data|constraints" "$K/drivers/mfd/rk808.c" | head -12

echo "=== what the vendor BSP used for the same rail (works there) ==="
grep -n -B4 -A14 'vdd_logic' /mnt/e/ubuntu/artifacts/live.dts | head -34
