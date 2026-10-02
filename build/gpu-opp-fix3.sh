#!/bin/bash
# gpu-opp-fix3.sh - same OPP override, but wrapped in / { } because dtc 1.7.2
# rejects a labelled bare node at file scope (outside the root block).
set -eu
K=/root/r36/linux-6.12.79
R=$K/arch/arm64/boot/dts/rockchip
D=$R/rk3326-xifan-r36max2.dts

echo "=== remove any previous attempt ==="
python3 - "$D" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
i = s.find("/* r36max2 GPU OPP")
j = s.find("/* GPU OPP workaround")
k = min(x for x in (i, j) if x >= 0) if (i >= 0 or j >= 0) else -1
if k >= 0:
    open(p, "w").write(s[:k].rstrip() + "\n")
    print("  stripped the old block at offset", k)
else:
    print("  nothing to strip")
PY

echo "=== append the corrected block ==="
cat >> "$D" <<'DTS'
/ {
	/* r36max2 GPU OPP: mainline's table asks 950 mV for the 200 MHz OPP, but on
	 * this board vdd_logic is already held at 975 mV by another consumer, so the
	 * regulator core rejects the request ("Restricting voltage,
	 * 975000-950000uV" -> -EINVAL) and panfrost aborts in devfreq init.
	 * Give the GPU a table whose floor is 975 mV. */
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
};

&gpu {
	operating-points-v2 = <&r36_gpu_opp>;
};
DTS

echo "=== rebuild the dtbs ==="
cd "$K"
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- dtbs 2>&1 | grep -E 'DTC|Error|error' | head -8

echo "=== verify: the gpu must now point at OUR table with 975 mV at 200 MHz ==="
for f in rk3326-xifan-r36max2 rk3326-xifan-r36max2-usbhost; do
  dtc -I dtb -O dts "$R/$f.dtb" 2>/dev/null > /tmp/chk.dts
  echo "--- $f.dtb"
  awk '/opp-table-gpu \{/,/^\t\};/' /tmp/chk.dts | head -12
  echo "   gpu operating-points-v2: $(awk '/gpu@ff400000 \{/,/^\t\};/' /tmp/chk.dts | grep operating-points)"
  echo "   old 950000 opp still referenced? $(grep -c '0xe7ef0' /tmp/chk.dts) occurrence(s) of 950000 in the tree"
done
ls -la "$R"/rk3326-xifan-r36max2*.dtb
