#!/bin/bash
# dev-gpu3.sh - is the RK817 DCDC1 actually unable to take 950 mV? probe the live
# regulator, and compare the BSP-style DT properties with what mainline expects.
set -uo pipefail
K=/root/r36/linux-6.12.79
DEV=192.168.31.210
PW=ubuntu
S() { sshpass -p "$PW" ssh -o ConnectTimeout=10 root@$DEV "$@" </dev/null 2>/dev/null; }

echo "=== mainline dt-bindings mode constants ==="
grep -nE "MODE|mode" "$K/include/dt-bindings/mfd/rk808.h" 2>/dev/null | head -12
echo "=== how rk808.c reads initial mode / volt ranges for RK817 DC1DC ==="
grep -nE "RK817|DCDC1|linear_range|of_get_regulator_init_mode|regulator-initial-mode|list_mode" "$K/drivers/mfd/rk808.c" 2>/dev/null | head -20
ls "$K/drivers/regulator" | grep -i rk8
grep -nE "\.min_uV|\.max_uV|volt_table|linear_min|n_voltages|RK817_REGULATOR|DCDC1" "$K/drivers/regulator/rk8xx-regulator.c" 2>/dev/null | head -25

echo "=== live probe: can the regulator take 950 mV at all? ==="
S 'for r in /sys/class/regulator/*; do
     n=$(cat $r/name 2>/dev/null)
     case "$n" in vdd_logic|vdd_arm|vcc_ddr)
       echo "  $n  ${r##*/}: min=$(cat $r/min_uV) max=$(cat $r/max_uV) now=$(cat $r/microvolts 2>/dev/null) mode=$(cat $r/mode 2>/dev/null) state=$(cat $r/state 2>/dev/null)"
       ;;
     esac
   done
   R=$(for r in /sys/class/regulator/*; do [ "$(cat $r/name 2>/dev/null)" = vdd_logic ] && echo $r; done)
   echo "  vdd_logic node: $R"
   echo 950000 > $R/microvolts 2>/tmp/err.txt && echo "  set 950000: OK -> $(cat $R/microvolts)" || echo "  set 950000 FAILED: $(cat /tmp/err.txt)"
   echo 1000000 > $R/microvolts 2>/tmp/err2.txt && echo "  set 1000000: OK -> $(cat $R/microvolts)" || echo "  set 1000000 FAILED: $(cat /tmp/err2.txt)"
   echo 975000 > $R/microvolts 2>/dev/null && echo "  set 975000: OK -> $(cat $R/microvolts)" || echo "  set 975000 FAILED"'

echo "=== the OPP table mainline rk3326.dtsi gives the gpu ==="
grep -n -A30 'gpu_opp_table:' "$K/arch/arm64/boot/dts/rockchip/rk3326.dtsi" | head -40
