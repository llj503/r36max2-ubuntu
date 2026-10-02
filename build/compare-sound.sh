#!/bin/bash
set -uo pipefail
D=/root/r36/linux-6.12.79/arch/arm64/boot/dts/rockchip
F=$D/rk3326-xifan-r36max2.dts
echo "=== our board dts: sound-related lines ==="
grep -nE 'sound|rk817|i2s|codec|hp-det|spk|amp|simple-audio|mclk' "$F" | head -40
echo
echo "=== the compiled dtb: sound node ==="
dtc -I dtb -O dts "$D/rk3326-xifan-r36max2.dtb" 2>/dev/null > /tmp/our.dts
awk '/rk817-sound \{/,/^\t\};/' /tmp/our.dts | head -40
echo "=== i2s node status in the dtb ==="
grep -n -B2 -A14 'i2s@ff540000\|i2s@ff140000\|i2s@\|i2s1' /tmp/our.dts | grep -E 'i2s@|status|sound-dai|pinctrl|clocks' | head -20
echo "=== codec node ==="
awk '/codec@1a|rk817@|codec@/{p=1} p{print} p&&/^\t\t\};/{exit}' /tmp/our.dts | head -30
echo "=== what does the vendor dts use for the i2s pins (phandle 0xca)? ==="
grep -n -B6 'phandle = <0xca>' /mnt/e/ubuntu/artifacts/live.dts | head -24
echo "=== vendor: any speaker/amp gpio or regulator ==="
grep -niE 'spk|speaker|amp|aw87|ns415' /mnt/e/ubuntu/artifacts/live.dts | head -20
