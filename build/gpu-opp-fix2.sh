#!/bin/bash
# gpu-opp-fix2.sh - revert the broken append, then give the GPU its own OPP table
# with 975 mV as the floor (the rail is already pinned there by another consumer).
set -eu
K=/root/r36/linux-6.12.79
R=$K/arch/arm64/boot/dts/rockchip
D=$R/rk3326-xifan-r36max2.dts

echo "=== where does the current gpu opp table come from? ==="
grep -n 'opp-table' "$R/rk3326.dtsi" | head -10
echo "--- tail of the board dts before we touch it ---"
tail -14 "$D"

echo "=== 1. drop the previously appended (broken) block ==="
python3 - "$D" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
marker = "/* GPU OPP workaround"
i = s.find(marker)
if i >= 0:
    s = s[:i].rstrip() + "\n"
    open(p, "w").write(s)
    print("  removed the old workaround block")
else:
    print("  nothing to remove")
PY

echo "=== 2. append a self-contained OPP table and point &gpu at it ==="
cat >> "$D" <<'DTS'

/* r36max2 GPU OPP: mainline's table asks 950 mV for the 200 MHz OPP, but on this
 * board vdd_logic is already held at 975 mV by another consumer, so the regulator
 * core rejects the request ("Restricting voltage, 975000-950000uV" -> -EINVAL) and
 * panfrost aborts in devfreq init.  Provide a table whose floor is 975 mV. */
r36_gpu_opp: opp-table-gpu {
	compatible = "operating-points-v2";

	opp-200000000 {
		opp-hz = /bits/ 64 <200000000>;
		opp-microvolt = <975000>;
	};
	opp-300000000 {
		opp-hz = /bits/ 64 <300000000>;
		opp-microvolt = <975000>;
	};
	opp-400000000 {
		opp-hz = /bits/ 64 <400000000>;
		opp-microvolt = <1050000>;
	};
	opp-480000000 {
		opp-hz = /bits/ 64 <480000000>;
		opp-microvolt = <1125000>;
	};
	opp-520000000 {
		opp-hz = /bits/ 64 <520000000>;
		opp-microvolt = <1175000>;
	};
};

&gpu {
	operating-points-v2 = <&r36_gpu_opp>;
};
DTS

echo "=== 3. rebuild ==="
cd "$K"
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- dtbs 2>&1 | grep -E 'DTC|Error|error|warning.*gpu' | head -10

echo "=== 4. verify both dtbs now carry 975000 at 200 MHz ==="
for f in rk3326-xifan-r36max2 rk3326-xifan-r36max2-usbhost; do
  dtc -I dtb -O dts "$R/$f.dtb" 2>/dev/null > /tmp/chk.dts
  echo "--- $f.dtb"
  grep -A4 'opp-table-gpu' /tmp/chk.dts | head -8
  awk '/opp-200000000 \{/{getline; getline; print "  200MHz voltage line:", $0}' /tmp/chk.dts | head -2
  grep -c 'opp-microvolt' /tmp/chk.dts | sed 's/^/  total opp-microvolt props: /'
done
ls -la "$R"/rk3326-xifan-r36max2*.dtb
