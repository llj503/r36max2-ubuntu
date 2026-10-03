#!/bin/bash
# k72-es-theme-install.sh - install the verified Art Book Next theme set (staged by
# k72-es-theme-prep.sh) where this ES build looks for themes, minus the artwork
# variants ROCKNIX itself drops.
#
# Order matters for diagnosis: run this AFTER smoke phase A (binary/window/GL proof with
# nothing to theme) and BEFORE phase B (list + launch), so a phase-B failure cannot be
# blamed on a missing theme when the theme is already in place.
#
# Mirrors ROCKNIX's makeinstall_target(): copy the set, delete the unused artwork
# directories AND the <include name="..."> lines that referenced them - deleting a
# directory without pruning its include leaves a theme.xml that errors on load.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 300 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
SRC=/root/theme-stage
DST=/root/.emulationstation/themes/art-book-next
echo "  host=$(hostname)"
[ -f "$SRC/theme.xml" ] || { echo "  !! $SRC/theme.xml missing - run k72-es-theme-prep.sh first"; exit 1; }
if [ -d "$DST" ]; then
  echo "  already installed: $DST ($(du -sh $DST 2>/dev/null | cut -f1))"
else
  echo "=== installing (this copies ~287 MB, then prunes) ==="
  mkdir -p "$DST"
  cp -a "$SRC"/. "$DST"/ || { echo "  !! copy failed"; exit 1; }
  echo "  before prune: $(du -sh $DST | cut -f1)"
  for a in artwork-circuit artwork-classic artwork-nintendont artwork-noir artwork-outline; do
    rm -rf "$DST/_inc/systems/$a"
    sed -i "/<include name=\"$a\"/d" "$DST/theme.xml" 2>/dev/null
  done
  echo "  after prune:  $(du -sh $DST | cut -f1)"
  echo "  artwork dirs left: $(ls $DST/_inc/systems 2>/dev/null | tr '\n' ' ')"
  echo "  dangling includes? $(grep -oE '<include name="[a-z-]+"' "$DST/theme.xml" | grep -cE 'circuit|classic|nintendont|noir|outline') (want 0)"
fi
python3 - <<'PY'
import xml.etree.ElementTree as ET
try:
    r = ET.parse("/root/.emulationstation/themes/art-book-next/theme.xml").getroot()
    print("  theme.xml parses: root=%s children=%d" % (r.tag, len(list(r))))
except Exception as exc:
    print("  !! theme.xml does not parse: %s" % exc)
PY
echo "  included system themes present: $(ls /root/.emulationstation/themes/art-book-next 2>/dev/null | grep -vE 'theme.xml|_inc|\.xml$|\.md$' | head -8 | tr '\n' ' ')"
echo "  pc theme present: $(ls -d /root/.emulationstation/themes/art-book-next/pc 2>/dev/null || echo 'no pc/ dir (falls back to the theme set default theme.xml)')"
echo
echo "=== point ThemeSet at it (Settings.cpp defaults ThemeSet to \"system-theme\", so"
echo "    installing files alone is NOT enough - ES looks in themes/<ThemeSet>/) ==="
python3 - <<'PY'
import os, re
p = "/root/.emulationstation/es_settings.cfg"
text = ""
if os.path.exists(p):
    text = open(p, errors="replace").read()
if "<stringList>" not in text:
    text = '<?xml version="1.0" encoding="utf-8"?>\n<stringList>\n</stringList>\n'
if re.search(r'<string\s+name="ThemeSet"', text):
    new = re.sub(r'<string\s+name="ThemeSet"[^>]*/>',
                 '<string name="ThemeSet" value="art-book-next" />', text)
    action = "replaced"
else:
    new = text.replace("</stringList>",
                       '  <string name="ThemeSet" value="art-book-next" />\n</stringList>', 1)
    action = "inserted"
open(p, "w").write(new)
import xml.etree.ElementTree as ET
r = ET.parse(p).getroot()
got = [e.get("value") for e in r if e.get("name") == "ThemeSet"]
print("  es_settings.cfg %s; ThemeSet=%s; root=%s entries=%d" % (action, got, r.tag, len(list(r))))
PY
EOS
echo "=== theme install step done ==="
