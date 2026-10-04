#!/bin/bash
# dev-wifiverify.sh - read back what r36-wifi-setup left on the card and in the
# rootfs, then clean the test files off the FAT partition.
set -uo pipefail
DEV=${DEV:-192.168.31.209}
S() { sshpass -p ubuntu ssh -o ConnectTimeout=15 root@$DEV "$@" </dev/null 2>/dev/null; }

S 'B=$(findfs LABEL=BOOT); mkdir -p /run/r36-boot
   mountpoint -q /run/r36-boot || mount -o shortname=mixed $B /run/r36-boot
   echo "=== files on BOOT (test leftovers) ==="; ls -l /run/r36-boot | grep -i wifi
   echo "=== wifi-status.txt ==="; sed "s/^/  /" /run/r36-boot/wifi-status.txt 2>/dev/null
   echo "=== generated conf: must contain NO plaintext passphrase ==="
   grep -c "#psk=" /etc/wpa_supplicant/wpa_supplicant-wlan0.conf | sed "s/^/  plaintext comment lines: /"
   grep -E "psk=|ssid=" /etc/wpa_supplicant/wpa_supplicant-wlan0.conf | sed -E "s/psk=[0-9a-f]+/psk=<hash>/" | sed "s/^/  /"
   ls -l /etc/wpa_supplicant/wpa_supplicant-wlan0.conf | awk "{print \"  perms:\", \$1}"
   echo "=== stamp ==="; cat /var/lib/r36-wifi/applied 2>/dev/null | sed "s/^/  /"
   echo "=== cleaning the test files off the card ==="
   rm -f /run/r36-boot/wifi.txt /run/r36-boot/wifi-status.txt /run/r36-boot/wifi-example.txt
   sync; ls /run/r36-boot | grep -i wifi | wc -l | sed "s/^/  wifi* files left: /"
   umount /run/r36-boot
   rm -f /root/wifi-cred.txt; echo "  device-side credential copy: $(ls /root/wifi-cred.txt 2>/dev/null || echo removed)"'
echo "=== still connected? ==="
S 'iw dev wlan0 link | head -2; ip -4 -br addr show wlan0'
