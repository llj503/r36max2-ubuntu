#!/bin/bash
# k72-wifi-crash.sh - 7.2.8 boots and the console works; what dies is the AIC
# driver: "SP/PC alignment exception, pc: 0x1, lr: cmd_mgr_msgind+0x108" in the
# aicwf_msg_busrx thread.  That is a call through a garbage function pointer.
# Disassemble the two builds and find which call it is.
set -uo pipefail
K72=/root/r36/k72test/wifi/drivers/aic8800/aic8800_fdrv/aic8800_fdrv.ko
K612=/root/r36/wifi/aic8800dc-linux-patched-main/drivers/aic8800/aic8800_fdrv/aic8800_fdrv.ko
SRC=/root/r36/k72test/wifi/drivers/aic8800/aic8800_fdrv

for f in "$K72" "$K612"; do
  echo "=== $(basename "$(dirname "$(dirname "$f")")")/$(basename "$f")  $f ==="
  [ -e "$f" ] || { echo "  missing"; continue; }
  aarch64-linux-gnu-objdump -d "$f" --disassemble=cmd_mgr_msgind 2>/dev/null | tail -40 | sed 's/^/  /'
done

echo "=== the source of cmd_mgr_msgind ==="
grep -rn "cmd_mgr_msgind" "$SRC"/.. 2>/dev/null | grep -v Binary | head -5
f=$(grep -rl "void cmd_mgr_msgind\|cmd_mgr_msgind(" "$SRC"/.. 2>/dev/null | grep -E "\.c$" | head -1)
echo "  file: $f"
[ -n "$f" ] && awk '/cmd_mgr_msgind\(/{f=1} f{print NR": "$0} f&&/^}/{exit}' "$f" | head -40 | sed 's/^/  /'
echo "=== crash check done ==="
