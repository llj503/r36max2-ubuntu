#!/bin/bash
# k72-es-theme-prep.sh - fetch the theme set ROCKNIX ships for this ES fork and verify
# it against their pinned sha256, but do NOT install it yet: phase A/B decide whether a
# theme is even needed (ES throws "File does not exist!" per system theme it cannot find).
#
# Doing the download now is deliberate: it is I/O only, so it does not fight the still
# running compile for CPU, and it means a theme failure costs one command instead of a
# download round trip.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
SHA=7ee1e93f2c4e4f7385b78680ecfa3828acf12bc616e2111d23cc66a524231125
URL=https://github.com/anthonycloccese
REV=9a50ef366e750aabfab29e6915a2867607212971
timeout 420 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV \
  "SHA=$SHA REV=$REV sh -s" <<'EOS'
cd /root || exit 1
T=art-book-next-$REV.tar.gz
url=https://github.com/anthonycaccese/art-book-next-es/archive/$REV.tar.gz
echo "  host=$(hostname)  es build progress: $(grep -oE '\[ *[0-9]+%\]' /tmp/esrn-build.log 2>/dev/null | tail -1)"
if [ ! -f "/root/$T" ]; then
  echo "=== download $url ==="
  timeout 300 curl -sSL -o "/root/$T" "$url" || { echo "  !! download failed"; exit 1; }
fi
ls -lh "/root/$T" | awk '{print "  size: " $5}'
echo "$SHA  /root/$T" > /root/theme.sha256
sha256sum -c /root/theme.sha256 2>&1 | sed 's/^/  verify: /'
if sha256sum -c /root/theme.sha256 >/dev/null 2>&1; then
  rm -rf /root/theme-stage && mkdir -p /root/theme-stage
  tar -xzf "/root/$T" -C /root/theme-stage --strip-components=1
  echo "  staged at /root/theme-stage: $(ls /root/theme-stage | tr '\n' ' ')"
  du -sh /root/theme-stage 2>/dev/null | awk '{print "  unpacked size: " $1}'
  echo "  theme.xml present: $(ls /root/theme-stage/theme.xml 2>/dev/null || echo NO)"
  echo "  bundled artwork dirs: $(ls /root/theme-stage/_inc/systems 2>/dev/null | tr '\n' ' ')"
  echo "  systems covered: $(ls /root/theme-stage 2>/dev/null | grep -vc '^_inc\|theme.xml')"
else
  echo "  !! sha mismatch - do not use it"
fi
EOS
echo "=== theme prep done (not installed yet, by design) ==="
