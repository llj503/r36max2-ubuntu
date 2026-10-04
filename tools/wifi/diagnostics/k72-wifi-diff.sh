#!/bin/bash
# k72-wifi-diff.sh - compare the WiFi init sequence between a known-good 6.12.79
# boot log and the 7.2.8 one, to find where they diverge.
set -uo pipefail
NEW=/e/ubuntu/logs/r36-boot-20261002-210115.txt
OLD=$(ls -t /e/ubuntu/logs/r36-boot-2026100*.txt | tail -1)
echo "old: $OLD"; echo "new: $NEW"
grep -m1 "kernel   :" "$OLD" | sed 's/^/  old kernel: /'
grep -m1 "kernel   :" "$NEW" | sed 's/^/  new kernel: /'

echo; echo "=== WiFi lines, OLD kernel ==="
grep -an -iE "aic|rwnx|wlan|firmware|regulatory|cmd_mgr" "$OLD" | head -32 | sed 's/^/  /'
echo; echo "=== WiFi lines, NEW kernel ==="
grep -an -iE "aic|rwnx|wlan|firmware|regulatory|cmd_mgr" "$NEW" | head -45 | sed 's/^/  /'
echo; echo "=== firmware file names mentioned ==="
echo "  old:"; grep -aoE "aic8800DC/[A-Za-z0-9_.-]+|[a-zA-Z0-9_]+\.bin" "$OLD" | sort -u | head -14 | sed 's/^/    /'
echo "  new:"; grep -aoE "aic8800DC/[A-Za-z0-9_.-]+|[a-zA-Z0-9_]+\.bin" "$NEW" | sort -u | head -14 | sed 's/^/    /'
echo; echo "=== RELEASE DATE / chip id lines ==="
grep -a "RELEASE DATE" "$OLD" | head -3 | sed 's/^/  old: /'
grep -a "RELEASE DATE" "$NEW" | head -3 | sed 's/^/  new: /'
grep -aoE "chip_id=[^ ,]*|chip_sub_id = [^ ,]*" "$OLD" | head -4 | sed 's/^/  old: /'
grep -aoE "chip_id=[^ ,]*|chip_sub_id = [^ ,]*" "$NEW" | head -4 | sed 's/^/  new: /'
