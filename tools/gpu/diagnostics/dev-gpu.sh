#!/bin/bash
# dev-gpu.sh - why does panfrost fail with "Couldn't set recommended OPP"?
set -uo pipefail
K=/root/r36/linux-6.12.79
D=$K/arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dts
DEV=192.168.31.210
PW=ubuntu
S() { sshpass -p "$PW" ssh -o ConnectTimeout=10 root@$DEV "$@" </dev/null 2>/dev/null; }

echo "=== our &gpu node ==="
sed -n '/^&gpu {/,/^};/p' "$D"
echo "=== our opp table / vdd_gpu regulator ==="
grep -n -A18 -E 'gpu_opp_table|operating-points-v2|vdd_gpu' "$D" | head -40
echo "=== the vendor dts gpu node (works on BSP) ==="
grep -n -B3 -A22 'gpu@ff400000' /mnt/e/ubuntu/artifacts/live.dts | head -40
echo "=== what the running kernel says right now ==="
S 'dmesg | grep -iE "panfrost|mali|opp|devfreq|gpu" | tail -12
   echo "--- clock ---"; cat /sys/kernel/debug/clk/clk_summary 2>/dev/null | grep -iE "gpu|aclk" | head -6
   echo "--- regulators ---"; grep -iE "vdd_gpu|gpu" /sys/kernel/debug/regulator/regulator_summary 2>/dev/null | head -6
   echo "--- opp ---"; ls /sys/devices/platform/*gpu/opp 2>/dev/null | head; cat /sys/kernel/debug/opp/*/* 2>/dev/null | head -8'
echo "=== fix the locale file (last run wrote a literal n) ==="
S 'printf "LANG=C.UTF-8\n" > /etc/default/locale; cat -A /etc/default/locale'
