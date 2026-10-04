#!/bin/bash
# k72-es-inputcfg.sh - install the generated joystick mapping where EmulationStation
# looks for it, so the first launch is usable without its configuration wizard (which
# needs a readable panel, and screenshots are blocked by weston's capture authority).
#
# It re-derives the GUID from the board before writing anything: if the DT or the SDL
# version changes, the numbers here would silently mislabel A/B/X/Y (that is exactly
# what a verbatim copy of Batocera's entry would have done on this board - their
# button order differs, see es-input-r36max2.cfg's header comment).
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
SRC=/mnt/e/ubuntu/packages/r36-emulationstation/es-input-r36max2.cfg
timeout 200 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
echo "  host=$(hostname)"
want=$(python3 - <<'PY'
import re
try:
    txt = open("/tmp/joy-guid.txt").read()
except OSError:
    txt = ""
print("use-the-live-probe" if not txt else "")
PY
)
echo "=== live GUID from SDL ==="
/usr/local/bin/r36-sdljoy 2>/dev/null | grep -E "guid=|name=" | sed 's/^/     /'
live=$(/usr/local/bin/r36-sdljoy 2>/dev/null | grep -oE 'guid=[0-9a-f]{32}' | head -1 | cut -d= -f2)
file=$(grep -oE 'deviceGUID="[0-9a-f]{32}"' /tmp/es-input.cfg 2>/dev/null | head -1 | cut -d'"' -f2)
echo "  live=$live"
[ -n "$live" ] || { echo "  !! probe gave no GUID - is r36-sdljoy built? (k72-es-joyprobe.sh)"; exit 1; }
EOS
# push the config, then verify the GUID inside it matches the live one
timeout 60 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'cat > /tmp/es-input.cfg' < "$SRC"
timeout 200 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
live=$(/usr/local/bin/r36-sdljoy 2>/dev/null | grep -oE 'guid=[0-9a-f]{32}' | head -1 | cut -d= -f2)
file=$(grep -oE 'deviceGUID="[0-9a-f]{32}"' /tmp/es-input.cfg | head -1 | cut -d'"' -f2)
echo "  live GUID=$live"
echo "  config GUID=$file"
[ "$live" = "$file" ] || { echo "  !! GUID MISMATCH - not installing; regenerate from the probe"; exit 1; }
mkdir -p /root/.emulationstation
if [ -f /root/.emulationstation/es_input.cfg ] && grep -q "$live" /root/.emulationstation/es_input.cfg; then
  echo "  already installed (GUID present in the existing file) - leaving it alone"
  grep -c "<inputConfig" /root/.emulationstation/es_input.cfg | sed 's/^/     existing entries: /'
else
  cp /tmp/es-input.cfg /root/.emulationstation/es_input.cfg
  echo "  installed to /root/.emulationstation/es_input.cfg"
fi
python3 -c "import xml.etree.ElementTree as ET; r=ET.parse('/root/.emulationstation/es_input.cfg').getroot(); print('  xml ok: %s with %d device block(s), %d <input>' % (r.tag, len(list(r)), len(list(r.iter('input')))))"
EOS
echo "=== input cfg install done ==="
