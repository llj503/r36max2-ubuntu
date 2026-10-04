#!/bin/bash
# shot.sh - grab what is on the R36 Max 2 panel right now, as a PNG.
# Reads /dev/fb0 over ssh (from WSL, where python3 exists) and converts it here.
set -uo pipefail
DEV=root@${DEV:-192.168.31.209}
PW=ubuntu
OUT=/mnt/e/ubuntu/shots
mkdir -p "$OUT"
TS=$(date +%H%M%S)

G=$(sshpass -p "$PW" ssh "$DEV" 'printf "%s %s\n" "$(cat /sys/class/graphics/fb0/virtual_size)" "$(cat /sys/class/graphics/fb0/bits_per_pixel)"')
VS=${G%% *}; BPP=${G##* }
W=${VS%,*}; VVH=${VS#*,}
LL=$(( W * BPP / 8 ))
# fbcon keeps a taller virtual buffer for scrolling; the visible part is 4 lines
# of 128x48 text on this panel = 768 of the 1536 reported rows
H=${SHOTS_H:-768}
[ "$VVH" -lt "$H" ] && H=$VVH
N=$(( LL * H ))
echo "grab ${W}x${H} of virtual ${VS}, bpp=$BPP line_length=$LL ($N bytes)"

sshpass -p "$PW" ssh "$DEV" "head -c $N /dev/fb0" > "/tmp/fb-$TS.raw"
ls -l "/tmp/fb-$TS.raw"
python3 /mnt/e/ubuntu/tools/capture/raw2png.py "/tmp/fb-$TS.raw" "$OUT/screen-$TS.png" "$W" "$VVH" "$BPP" "$LL" "$H"
rm -f "/tmp/fb-$TS.raw"
ls -la "$OUT/screen-$TS.png"
echo "SHOT=$OUT/screen-$TS.png"
