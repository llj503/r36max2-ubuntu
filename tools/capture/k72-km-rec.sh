#!/bin/bash
# k72-km-rec.sh - (re)open a capture window on the two uinput devices the bridge
# creates, so the user can press things at their own pace and we read it after.
#   bash k72-km-rec.sh [seconds]
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
WIN=${1:-300}

# always push the current copy first - the transient unit keeps running the old
# file otherwise, which is how a fixed wheel mapping appeared to do nothing
sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV "cat > /usr/local/bin/r36-keymapper.py" \
  < /mnt/e/ubuntu/packages/r36-keymapper/r36-keymapper.py
timeout 90 sshpass -p $PW ssh -o ConnectTimeout=20 root@$DEV 'sh -s' <<EOS
chmod 755 /usr/local/bin/r36-keymapper.py
echo "  pushed: \$(sha256sum /usr/local/bin/r36-keymapper.py | cut -c1-16)"
systemctl stop r36-km-test 2>/dev/null
sleep 1
systemd-run --unit=r36-km-test --quiet /usr/bin/python3 /usr/local/bin/r36-keymapper.py -v
sleep 2.5                                  # uinput needs a moment before the nodes exist
echo 0 > /sys/class/graphics/fb0/blank
KBD=\$(for d in /sys/class/input/event*; do [ "\$(cat \$d/device/name 2>/dev/null)" = "r36 joypad keyboard" ] && basename \$d; done)
MOU=\$(for d in /sys/class/input/event*; do [ "\$(cat \$d/device/name 2>/dev/null)" = "r36 joypad mouse" ] && basename \$d; done)
echo "  bridge: \$(systemctl is-active r36-km-test)   keyboard=\${KBD:-MISSING} mouse=\${MOU:-MISSING}"
pkill -x evtest 2>/dev/null; sleep 1
rm -f /tmp/km-kbd.txt /tmp/km-mouse.txt
[ -n "\$KBD" ] && ( timeout $WIN evtest /dev/input/\$KBD > /tmp/km-kbd.txt 2>&1 & )
[ -n "\$MOU" ] && ( timeout $WIN evtest /dev/input/\$MOU > /tmp/km-mouse.txt 2>&1 & )
echo "  window ${WIN}s open from \$(date +%H:%M:%S) until about \$(date -d "+${WIN} seconds" +%H:%M:%S 2>/dev/null || echo +${WIN}s)"
EOS
echo "=== recording; press and move now ==="
