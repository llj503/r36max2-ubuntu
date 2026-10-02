#!/bin/bash
# gpu-opp-fix.sh - raise the GPU's 200 MHz OPP from 950 mV to 975 mV, because
# vdd_logic is already held at 975 mV by another consumer and the regulator core
# refuses min>max ("Restricting voltage, 975000-950000uV" -> panfrost -22).
set -eu
K=/root/r36/linux-6.12.79
R=$K/arch/arm64/boot/dts/rockchip
D=$R/rk3326-xifan-r36max2.dts

echo "=== how is the gpu opp table labelled in rk3326.dtsi? ==="
grep -n -B2 -A4 'opp-table-1' "$R/rk3326.dtsi" | head -20

if grep -q 'gpu_opp_table:' "$R/rk3326.dtsi"; then
	TARGET='&gpu_opp_table {'
elif grep -qE '^\s*[a-z_0-9]+: opp-table-1 \{' "$R/rk3326.dtsi"; then
	LBL=$(grep -oE '[a-z_0-9]+: opp-table-1 \{' "$R/rk3326.dtsi" | head -1 | cut -d: -f1)
	echo "  label found: $LBL"
	TARGET="&$LBL {"
else
	TARGET=''
fi

if grep -q 'GPU OPP workaround' "$D"; then
	echo "=== already patched ==="
else
	{
		echo
		echo "/* GPU OPP workaround: vdd_logic is pinned at 975 mV by another consumer,"
		echo " * so the 200 MHz OPP may not ask for 950 mV (regulator core returns -EINVAL"
		echo " * and panfrost aborts devfreq init). */"
		if [ -n "$TARGET" ]; then
			echo "$TARGET"
			echo "	opp-200000000 {"
			echo "		opp-microvolt = <975000>;"
			echo "	};"
			echo "};"
		else
			echo "opp-table-1 {"
			echo "	opp-200000000 {"
			echo "		opp-microvolt = <975000>;"
			echo "	};"
			echo "};"
		fi
	} >> "$D"
	echo "=== appended to the board dts ==="
	tail -12 "$D"
fi

echo "=== rebuild the dtbs ==="
cd "$K"
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- dtbs 2>&1 | grep -E 'DTC|Error|error' | head -8

echo "=== verify the compiled dtb ==="
for f in rk3326-xifan-r36max2 rk3326-xifan-r36max2-usbhost; do
  dtc -I dtb -O dts "$R/$f.dtb" 2>/dev/null > /tmp/chk.dts
  echo "--- $f.dtb"
  grep -A3 'opp-200000000 {' /tmp/chk.dts | head -4
done
ls -la "$R"/rk3326-xifan-r36max2*.dtb
