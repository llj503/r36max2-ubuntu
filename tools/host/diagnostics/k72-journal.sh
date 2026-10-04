#!/bin/bash
# k72-journal.sh - the card is in the reader, and the rootfs has a persistent
# journal, so we can read the *whole* 7.2.8 boot offline instead of guessing
# from the grepped r36-boot.txt.  Mount read-only, dump the WiFi init, and
# compare it against the known-good 6.12 sequence.
set -uo pipefail

echo "=== find the card ==="
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT -b 2>/dev/null | grep -v loop | head -20
DEV=$(lsblk -rno NAME,FSTYPE,SIZE 2>/dev/null | awk '$2=="ext4" && $3>50000000000 {print "/dev/"$1; exit}')
[ -n "$DEV" ] || { echo "no 58 GB ext4 partition found"; exit 1; }
echo "  root partition: $DEV ($(lsblk -dno SIZE "$DEV"))"

M=/mnt/cardroot
mkdir -p "$M"
mount -o ro "$DEV" "$M" || { echo "  mount failed"; exit 1; }
echo "  mounted ro at $M"

echo "=== boots recorded in the journal ==="
journalctl -D "$M/var/log/journal" --list-boots --no-pager 2>&1 | tail -6

echo "=== last boot: full WiFi init (this is what r36-boot.txt never showed) ==="
journalctl -D "$M/var/log/journal" -b -1 -k --no-pager 2>/dev/null | \
  grep -aiE "aic|AICWF|usb 1-1|firmware|Upload|chip_id|chip_sub|cmd_mgr|regulatory|rwnx|wlan0" | \
  head -60 | sed 's/^/  /'

echo "=== the crash, in full ==="
journalctl -D "$M/var/log/journal" -b -1 -k --no-pager 2>/dev/null | \
  awk '/Internal error|alignment exception/{f=1} f{print} /end trace/{f=0}' | head -45 | sed 's/^/  /'

echo "=== dmesg buffer if it was saved anywhere ==="
ls -l "$M/var/log"/dmesg* "$M/var/lib/r36"* 2>/dev/null | sed 's/^/  /'
echo "  (also check: $(grep -c . "$M/etc/modules-load.d/r36max2.conf" 2>/dev/null) modules listed in modules-load.d)"
cat "$M/etc/modules-load.d/r36max2.conf" 2>/dev/null | sed 's/^/    /'

umount "$M" && echo "  unmounted"
echo "=== journal dump done ==="
