#!/bin/bash
set -uo pipefail
cd /tmp
for name in "opp-table-gpu" "opp-table" "opp_table_gpu" "opp-table@0"; do
  cat > t.dts <<EOF
/dts-v1/;
/ {
	#address-cells = <1>;
	#size-cells = <0>;
	r36_gpu_opp: $name {
		compatible = "operating-points-v2";
		opp-200000000 {
			opp-hz = /bits/ 64 <200000000>;
			opp-microvolt = <975000>;
		};
	};
};
EOF
  out=$(dtc -I dts -O dtb -o /dev/null t.dts 2>&1 | head -2)
  printf "  %-16s -> %s\n" "$name" "${out:-OK}"
done
echo "=== and with a label but no unit address, at root, in the real file's style ==="
printf '/dts-v1/;\nr36_gpu_opp: opp-table-gpu {\n\tcompatible = "operating-points-v2";\n};\n' > t2.dts
dtc -I dts -O dtb -o /dev/null t2.dts 2>&1 | head -3 || true
echo "=== dtc version ==="
dtc --version | head -2
