#!/bin/bash
# Fix the two cosmetic fields on the live status page, then report state.
set -uo pipefail
DEV=root@192.168.31.210
PW=ubuntu
S() { sshpass -p "$PW" ssh "$DEV" "$@"; }

cat > /tmp/patch-screen.sh <<'EOS'
f=/usr/local/sbin/r36-status-screen
cp -n "$f" /root/r36-status-screen.bak2 2>/dev/null
# IP without the /24 prefix length
sed -i "s#| awk '{print \$3}')#| awk '{print \$3}' | cut -d/ -f1)#" "$f"
# drop the leading colon that "RELEASE DATE:" leaves behind
sed -i "s#sed \"s/.\*RELEASE DATE//;s/\[ \t\]\*\$//\")#sed \"s/.*RELEASE DATE//;s/^[ :]*//;s/[ :]*\$\")#" "$f"
sh -n "$f" && systemctl restart r36-status-screen && echo PATCHED
grep -nE "WLAN=|DRV=" "$f" | head -4
EOS
sshpass -p "$PW" scp -q /tmp/patch-screen.sh "$DEV:/tmp/"
S "sh /tmp/patch-screen.sh"

echo "=== uptime / boot time ==="
S 'cat /proc/uptime; echo -n "boot: "; uptime -s; date -Is'
S 'systemctl show r36-status-screen -p ExecMainStartTimestamp -p NRestarts -p ActiveState'

echo "=== apt progress ==="
S 'tail -2 /root/setup.log; pgrep -c apt-get || echo "apt-get finished"; dpkg -l 2>/dev/null | awk "/^ii/{n++} END {print \"installed: \" n}"'
