#!/bin/bash
# k72-console-no-blank.sh - make "never blank the console" survive a reboot.
# setterm at runtime only lasts until the next boot, and on a board with no
# keyboard a blanked panel is indistinguishable from a dead one (we just lost
# twenty minutes to exactly that confusion).  kbd is installed now, so the
# supported way is /etc/kbd/config, which setupcon applies at boot.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 90 sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV 'sh -s' <<'EOS'
echo "=== /etc/kbd/config before ==="
if [ -e /etc/kbd/config ]; then
  grep -nE "^(BLANK_TIME|POWERDOWN_TIME|FORCE_FONT_LOAD)" /etc/kbd/config | sed 's/^/  /'
  sed -i 's/^BLANK_TIME=.*/BLANK_TIME=0/; s/^POWERDOWN_TIME=.*/POWERDOWN_TIME=0/' /etc/kbd/config
else
  printf 'BLANK_TIME=0\nPOWERDOWN_TIME=0\n' > /etc/kbd/config
  echo "  created /etc/kbd/config"
fi
grep -nE "^(BLANK_TIME|POWERDOWN_TIME)" /etc/kbd/config | sed 's/^/  after: /'
echo
echo "=== does anything else re-enable blanking? ==="
grep -rIl --exclude-dir=proc "blank" /etc/systemd/system/ /etc/init.d/ 2>/dev/null | head -5 | sed 's/^/  /'
systemctl list-unit-files 2>/dev/null | grep -iE "console-?blank|screenblank" | sed 's/^/  unit: /'
echo "  keyboard-setup enabled: $(systemctl is-enabled keyboard-setup 2>/dev/null || echo n/a)"
echo
echo "=== apply now and confirm the live state matches ==="
setupcon 2>&1 | head -3 | sed 's/^/  setupcon: /'
echo 0 > /sys/class/graphics/fb0/blank
for t in 1 2 3 4 5 6; do [ -e /dev/tty$t ] && setterm -blank 0 -powerdown 0 -store > /dev/tty$t 2>/dev/null; done
echo "  fb0 blank: $(cat /sys/class/graphics/fb0/blank)"
echo "  screensaver timers (0 = off): $(cat /sys/module/kernel/parameters/consoleblank 2>/dev/null)"
echo "  (consoleblank kernel param is still $(cat /sys/module/kernel/parameters/consoleblank 2>/dev/null); setupcon sets it via rc_lock/vt ioctl at boot)"
EOS
echo "=== console blanking configured off ==="
