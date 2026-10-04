#!/bin/bash
# boot-verify-device.sh - read-only pass over a booted card, run over SSH from the build
# host, answering the questions scripts/image can only assert about *files*: did the
# kernel actually take the dtb, do the buttons actually report, did WiFi join, is the GPU
# bound, is ES present and where.  Nothing here writes to the device.
#
#   DEV=192.168.0.141 bash tools/host/verify/boot-verify-device.sh
#
# Run it on a known-good card BEFORE flashing anything over it: half the value is having
# a baseline to diff the post-reflash output against (measured 2026-10-04 against the v20
# card in the handheld, kernel 7.2.8, 28213 s uptime).
set -u
DEV=${DEV:?usage: DEV=192.168.0.141 bash boot-verify-device.sh}
export SSHPASS=${SSHPASS:-ubuntu}          # documented debug default; SECURITY.md says change it
SSHOPTS="-o ConnectTimeout=25 -o StrictHostKeyChecking=accept-new"
OUT=${OUT:-/dev/stdout}

probe() { timeout "${TMO:-300}" sshpass -e ssh $SSHOPTS root@"$DEV" 'sh -s' <<'EOS'
echo "== identity =="
echo "  kernel : $(uname -r)"
echo "  uptime : $(cut -d' ' -f1 /proc/uptime) s"
echo "  dtb    : $(tr -d '\0' < /sys/firmware/devicetree/base/model 2>/dev/null)"
echo "  cmdline: $(cat /proc/cmdline)"
echo "  root   : $(cat /proc/cmdline | tr ' ' '\n' | grep -E '^root=' || echo '(initrd-selected)')"

echo "== display / GPU =="
echo "  drm    : $(ls /sys/class/drm/ 2>/dev/null | tr '\n' ' ')"
for c in /sys/class/backlight/*; do
  [ -d "$c" ] || continue
  echo "  light  : $(basename "$c") $(cat "$c/brightness" 2>/dev/null)/$(cat "$c/max_brightness" 2>/dev/null)"
done
echo "  panfrost bound: $(ls -d /sys/bus/platform/drivers/panfrost/ff* 2>/dev/null | tr '\n' ' ')"
echo "  render nodes  : $(ls /dev/dri/ 2>/dev/null | tr '\n' ' ')"
echo "  fbcon     : $(cat /sys/class/vtconsole/vtcon1/name 2>/dev/null) state=$(cat /sys/class/vtconsole/vtcon1/bind 2>/dev/null)"

echo "== input =="
# Print the device blocks verbatim. /sys/class/input/js0/device has no keys/axes files
# (measured on the v20 card), so a "keys=N" guess reads 0 for a pad that really has
# 17 buttons and 4 axes; the K:/A:/B: masks here are the truth, and B: FF is rumble.
awk 'BEGIN{RS=""} /joypad|adc-keys|pwrkey/ {gsub(/\n/, "\n      "); print "    " $0 "\n"}' /proc/bus/input/devices
for j in /dev/input/js*; do
  [ -e "$j" ] || continue
  echo "  $j -> $(cat "/sys/class/input/$(basename "$j")/device/name" 2>/dev/null)"
done
echo "  by-path: $(ls /dev/input/by-path/ 2>/dev/null | tr '\n' ' ')"

echo "== wifi =="
echo "  addr   : $(ip -br addr show wlan0 2>/dev/null)"
echo "  link   : $(iw dev wlan0 link 2>/dev/null | sed -n '1,3p' | tr '\n' ' ')"
echo "  regdom : $(iw reg get 2>/dev/null | grep -m1 country)"
echo "  scan   : $(timeout 8 iw dev wlan0 scan 2>/dev/null | grep -c '^BSS ') networks in 8 s"
echo "  route  : $(ip route 2>/dev/null | grep '^default' | head -1)"
echo "  units  : service=$(systemctl is-active r36-wifi-setup.service 2>/dev/null) wpa=$(systemctl is-active r36-wpa@wlan0.service 2>/dev/null) timer=$(systemctl is-active r36-wifi-setup.timer 2>/dev/null)"

echo "== services (every r36-* unit, name-agnostic) =="
systemctl list-unit-files 'r36-*' --no-pager --no-legend 2>/dev/null | sed 's/^/  /'
echo "  active now:"
systemctl list-units 'r36-*' --all --no-pager --no-legend 2>/dev/null | sed 's/^/    /'
echo "  weston (must NOT be active): $(systemctl is-active weston 2>/dev/null)"
echo "  failed units: $(systemctl list-units --state=failed --no-pager --no-legend 2>/dev/null | wc -l)"

echo "== storage =="
df -h / 2>/dev/null | tail -1 | sed 's/^/  /'
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT 2>/dev/null | grep -E 'mmcblk|NAME' | sed 's/^/  /'

echo "== EmulationStation =="
# v20 built ES on the board (/root/es); v21 installs the cross-built one at
# /usr/local/bin.  List every candidate - one path that only exists in one layout
# would read as "ES missing" in the other.
for c in /usr/local/bin/emulationstation /usr/bin/emulationstation /root/es/emulationstation; do
  printf '  %-34s %s\n' "$c" "$([ -x "$c" ] && stat -c '%s B' "$c" || echo absent)"
done
echo "  launcher : $(ls -l /usr/local/bin/r36-es 2>/dev/null | awk '{print $5" B"}' || echo MISSING)"
echo "  /etc/emulationstation : $(ls /etc/emulationstation 2>/dev/null | tr '\n' ' ')"
echo "  ~/.emulationstation   : $(ls /root/.emulationstation 2>/dev/null | tr '\n' ' ')"
echo "  themes                : $(ls -d /root/.emulationstation/themes/* /usr/share/emulationstation/themes/* 2>/dev/null | tr '\n' ' ')"
echo "  es running            : $(pgrep -c emulationstatio 2>/dev/null; true)"

echo "== dmesg red flags =="
dmesg 2>/dev/null | grep -iE 'vblank|flip_done|unknown symbol|not loaded|failed to probe|error -' | tail -12 | sed 's/^/  /'
echo "  (AICWFDBG(LOGERROR) patch_tbl lines are normal chatter from this driver and are filtered out)"
dmesg 2>/dev/null | grep -c 'AICWFDBG(LOGERROR)' | sed 's/^/  aic LOGERROR-count: /'
EOS
}

echo "# boot-verify against $DEV  $(date -Is)" | tee "$OUT"
probe 2>&1 | tee -a "$OUT"
echo "# done $(date -Is) - read-only, nothing was written to the device" | tee -a "$OUT"
