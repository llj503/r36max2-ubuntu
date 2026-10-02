#!/bin/bash
set -uo pipefail
K=/root/r36/linux-6.12.79
DTB=$K/arch/arm64/boot/dts/rockchip/rk3326-xifan-r36max2.dtb
dtc -I dtb -O dts "$DTB" 2>/dev/null > /tmp/full.dts
echo "=== every opp node in the compiled dtb ==="
grep -n -B4 -A2 'opp-microvolt' /tmp/full.dts | head -60
echo "=== which node does the gpu point at (phandle 0x94) ==="
grep -n 'phandle = <0x94>' /tmp/full.dts
awk '/phandle = <0x94>/{for(i=NR-30;i<NR;i++) print buf[i%31]}' /tmp/full.dts 2>/dev/null | head -0
python3 - <<'PY'
import re
src = open('/tmp/full.dts').read()
# find the node block that declares phandle 0x94
for m in re.finditer(r'([A-Za-z0-9_@,.-]+) \{([^{}]*(?:\{[^{}]*\}[^{}]*)*)\}', src, re.S):
    if 'phandle = <0x94>' in m.group(2):
        print("node:", m.group(1))
        print(m.group(2).strip()[:600])
        break
PY
