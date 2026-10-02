#!/bin/bash
# dev-wifitest.sh - exercise r36-wifi-setup on the live card, carefully:
#   phase 1: only generate the config and compare it against the one the box is
#            using right now (no service restart -> no risk of losing SSH)
#   phase 2: install the units, drop wifi.txt on BOOT, run it for real
# The passphrase never gets printed; only lengths and the resulting PSK hash.
set -uo pipefail
DEV=${DEV:-192.168.31.209}
S() { sshpass -p ubuntu ssh -o ConnectTimeout=15 root@$DEV "$@" </dev/null 2>/dev/null; }
PHASE=${1:-1}

sshpass -p ubuntu scp -q /mnt/e/ubuntu/build/wifi-cred.txt "$DEV:/root/wifi-cred.txt"
sshpass -p ubuntu scp -q /mnt/e/ubuntu/build/r36-wifi-setup "$DEV:/root/r36-wifi-setup"
S 'chmod 755 /root/r36-wifi-setup; ls -l /root/r36-wifi-setup'

if [ "$PHASE" = "1" ]; then
  echo "=== phase 1: generate only, compare hashes ==="
  S 'SSID=$(grep "^Name=" /root/wifi-cred.txt | cut -d= -f2- | tr -d "\r");
     PSK=$(grep "^Passphrase=" /root/wifi-cred.txt | cut -d= -f2- | tr -d "\r");
     echo "  ssid=[$SSID] psk-length=${#PSK}";
     { printf "ctrl_interface=DIR=/run/wpa_supplicant GROUP=netdev\nupdate_config=1\ncountry=CN\n\n"; wpa_passphrase "$SSID" "$PSK" | grep -v "^[[:space:]]*#psk="; } > /tmp/w2.conf;
     echo "  generated (passphrase lines stripped):"; sed -E "s/psk=[0-9a-f]+/psk=<hash>/" /tmp/w2.conf | sed "s/^/    /";
     echo "  live conf psk hash: $(grep -oE "psk=[0-9a-f]{8}" /etc/wpa_supplicant/wpa_supplicant-wlan0.conf | head -1)";
     echo "  new   conf psk hash: $(grep -oE "psk=[0-9a-f]{8}" /tmp/w2.conf | head -1)";
     echo "  live ssid line    : $(grep -c "ssid=" /etc/wpa_supplicant/wpa_supplicant-wlan0.conf) vs new $(grep -c "ssid=" /tmp/w2.conf)"'
  echo "  (if the two hashes match, the apply path cannot make things worse)"
fi

if [ "$PHASE" = "2" ]; then
  echo "=== phase 2: install + real apply ==="
  S 'cp -f /root/r36-wifi-setup /usr/local/sbin/r36-wifi-setup; chmod 755 /usr/local/sbin/r36-wifi-setup;
     cp -f /etc/wpa_supplicant/wpa_supplicant-wlan0.conf /root/wpa-backup.conf;
     B=$(findfs LABEL=BOOT); echo "  BOOT=$B";
     mkdir -p /run/r36-boot; mount -o shortname=mixed $B /run/r36-boot || { echo "  mount failed"; exit 1; }
     grep "^Name=" /root/wifi-cred.txt | sed "s/^Name=/SSID=/" > /run/r36-boot/wifi.txt
     grep "^Passphrase=" /root/wifi-cred.txt | sed "s/^Passphrase=/PSK=/" >> /run/r36-boot/wifi.txt
     echo "COUNTRY=CN" >> /run/r36-boot/wifi.txt
     echo "  wrote wifi.txt:"; sed -E "s/^(PSK=).*/\1<redacted>/" /run/r36-boot/wifi.txt | sed "s/^/    /"'
  echo "  --- running it (will restart wpa_supplicant; expect a few seconds of SSH stall) ---"
  S 'umount /run/r36-boot 2>/dev/null; rm -f /var/lib/r36-wifi/applied; cd /root && timeout 150 ./r36-wifi-setup; echo "  exit=$?"'
  echo "  --- result on the card ---"
  S 'cat /run/r36-boot/wifi-status.txt 2>/dev/null | sed "s/^/  /" || { B=$(findfs LABEL=BOOT); mkdir -p /run/r36-boot; mount -o shortname=mixed $B /run/r36-boot; cat /run/r36-boot/wifi-status.txt | sed "s/^/  /"; }'
  echo "  --- link state now ---"
  S 'iw dev wlan0 link | head -3; ip -4 -br addr show wlan0; systemctl is-active r36-wpa@wlan0.service'
fi
