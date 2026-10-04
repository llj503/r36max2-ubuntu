#!/bin/bash
# k72-watch-dev.sh - the R36 Max 2 has not answered on 192.168.31.209 since we
# rebooted it with the corrected dtb.  Watch the LAN and tell us the moment it
# comes back (and on which address), instead of re-running probes by hand.
#
# Every round: try the known address, then sweep the ARP table for anything
# new that answers SSH on port 22.  Exits as soon as it gets a shell.
set -uo pipefail
PW=ubuntu
ROUNDS=${ROUNDS:-150}          # 150 x ~8s = ~20 min
KNOWN="192.168.31.209 192.168.31.210 192.168.31.208 192.168.31.211 192.168.31.212"

try() {
  sshpass -p $PW ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no \
    root@"$1" 'echo ok' >/dev/null 2>&1
}

for i in $(seq 1 $ROUNDS); do
  for ip in $KNOWN; do
    if try "$ip"; then
      echo "[$(date +%H:%M:%S)] round $i: BACK ON $ip"
      sshpass -p $PW ssh -o ConnectTimeout=6 root@$ip \
        'echo "  kernel : $(uname -r)"; echo "  uptime : $(cut -d" " -f1 /proc/uptime)s";
         echo "  wlan0  : $(ip -4 -br addr show wlan0 2>/dev/null | tr -s " ")";
         echo "  failed : $(systemctl --failed --no-legend --plain | wc -l) units";
         echo "  joypad : $(ls /sys/class/input/ 2>/dev/null | grep -c event) events, retrogame=$(cat /sys/bus/platform/drivers/rocknix-singleadc-joypad/*/.state 2>/dev/null | head -1)";
         echo "  modprobe rocknix: $(lsmod | grep -c rocknix) loaded";
         echo "  rumble gpio state: $(cat /sys/kernel/debug/gpio 2>/dev/null | grep -iE "gpio-527|gpio-0-15" | tr "\n" " ")"' 2>&1
      echo "=== FOUND ==="
      exit 0
    fi
  done
  # broad sweep: refresh ARP then probe anyone new
  for j in $(seq 1 254); do ping -c1 -W1 192.168.31.$j >/dev/null 2>&1 & done
  sleep 4
  for ip in $(arp -an 2>/dev/null | grep -oE '192\.168\.31\.[0-9]+' | sort -u); do
    case " $KNOWN " in *" $ip "*) continue;; esac
    if try "$ip"; then
      echo "[$(date +%H:%M:%S)] round $i: NEW ADDRESS $ip"
      echo "=== FOUND ==="
      exit 0
    fi
  done
  echo "[$(date +%H:%M:%S)] round $i: nothing"
  sleep 2
done
echo "[$(date +%H:%M:%S)] gave up after $ROUNDS rounds - device is offline (off, suspended, or failed to boot)"
echo "=== NOT FOUND ==="
exit 1
