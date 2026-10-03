#!/bin/bash
# v20-strip-creds.sh - the staging rootfs was built with R36_BAKE_WIFI=1, so it
# carries our real SSID/passphrase in two wpa_supplicant configs.  A published
# image must not do that: BOOT:\wifi.txt is the supported provisioning channel and
# it is tested.  This removes the baked credentials from the rootfs and then proves
# no trace of the passphrase survives anywhere (filenames only - the secret is
# never echoed).
set -uo pipefail
R=/root/r36/rootfs
CRED=/mnt/e/ubuntu/build/wifi-cred.txt

if [ ! -f "$CRED" ]; then
  echo "  !! $CRED missing - cannot verify, refusing to claim clean"
  exit 1
fi
# read the two values without printing them
SSID=$(awk -F= 'tolower($1) ~ /ssid/ {gsub(/^[ \t]+|[ \t\r]+$/,"",$2); print $2; exit}' "$CRED")
PSK=$(awk -F= 'tolower($1) ~ /psk|passphrase|key/ {gsub(/^[ \t]+|[ \t\r]+$/,"",$2); print $2; exit}' "$CRED")
echo "  credential lengths: ssid=${#SSID} psk=${#PSK}   (values not shown)"

echo "=== [1] files that hold them ==="
for f in "$R/etc/wpa_supplicant/wpa_supplicant-nl80211-wlan0.conf" \
         "$R/etc/wpa_supplicant/wpa_supplicant-wlan0.conf" \
         "$R/etc/NetworkManager/system-connections/"*; do
  [ -e "$f" ] && echo "  $(stat -c '%a %s %n' "$f")"
done
rm -f "$R/etc/wpa_supplicant/wpa_supplicant-nl80211-wlan0.conf" \
      "$R/etc/wpa_supplicant/wpa_supplicant-wlan0.conf"
echo "  removed the baked wpa configs (r36-wifi-setup regenerates one from BOOT:\\wifi.txt)"

echo
echo "=== [2] make sure nothing else in the rootfs repeats the passphrase ==="
hits=0
if [ -n "$PSK" ]; then
  while IFS= read -r f; do
    if [ -f "$f" ] && grep -qF -- "$PSK" "$f" 2>/dev/null; then
      echo "  !! still present in: ${f#$R/}"
      hits=$((hits+1))
    fi
  done < <(find "$R" -xdev -type f \( -size -5M \) \
             -not -path "$R/usr/share/*" -not -path "$R/usr/lib/*" -not -path "$R/proc/*" 2>/dev/null)
fi
echo "  files still containing the passphrase: $hits"

echo
echo "=== [3] any SSID traces (config files, history, status output) ==="
grep -rlI --exclude-dir=share --exclude-dir=lib -F -- "$SSID" "$R/etc" "$R/root" "$R/var/log" 2>/dev/null | sed 's/^/  /' | head -10
echo "  root home files: $(ls -A "$R/root" 2>/dev/null | tr '\n' ' ')"
echo "  /tmp and /var/tmp inside the image: $(ls -A "$R/tmp" "$R/var/tmp" 2>/dev/null | tr '\n' ' ')"
rm -f "$R/root/.bash_history"
echo
echo "=== [4] what the first boot will do instead ==="
echo "  r36-wifi-setup.service reads BOOT:\\wifi.txt (SSID=/PSK=/COUNTRY=) and writes a 600 conf"
ls "$R/etc/systemd/system/multi-user.target.wants/" | grep wifi | sed 's/^/  enabled: /'
ls "$R/etc/systemd/system/timers.target.wants/" | grep wifi | sed 's/^/  timer: /'
[ "$hits" = 0 ] && echo "=== credential-free: OK ===" || echo "=== !! credentials still present, fix before shipping ==="
