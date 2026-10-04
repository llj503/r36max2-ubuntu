#!/bin/bash
# extract-vendor-blobs.sh - pull the three vendor u-boot blobs off an SD card
# that boots the stock ArkOS/EmuELEC system, into sources/vendor/.
#
# These blobs (Rockchip idbloader / uboot / trust) are proprietary and are NOT
# distributed with this repo - they are dd'd from a card you already have.
# Offsets are the standard Rockchip layout and are the same ones pack-v20.sh
# used (32 KiB / 8 MiB / 12 MiB).
#
# Usage: sudo bash scripts/extract-vendor-blobs.sh /dev/sdX
set -euo pipefail
DEV="${1:?usage: $0 /dev/sdX (the whole device, not a partition)}"
OUT="$(dirname "$0")/../sources/vendor"
mkdir -p "$OUT"
# unbootable-region sizes are fixed by the Rockchip boot ROM layout
dd if="$DEV" of="$OUT/idbloader.img" bs=512 skip=64    count=8192   status=none   # 32 KiB .. 4 MiB
dd if="$DEV" of="$OUT/uboot.img"     bs=512 skip=16384 count=8192   status=none   # 8 MiB  .. 12 MiB
dd if="$DEV" of="$OUT/trust.img"     bs=512 skip=24576 count=8192   status=none   # 12 MiB .. 16 MiB
sha256sum "$OUT"/idbloader.img "$OUT"/uboot.img "$OUT"/trust.img
echo "Blobs staged in $OUT."
echo "Copy the three hashes into sources/vendor-blobs.sha256 (or let scripts/image record them on first use)."
