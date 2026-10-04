#!/bin/bash
# k72-es-theme-install.sh - put the verified Art Book Next set where this ES looks for
# themes, point ThemeSet at it, and PROVE the installed tree has no broken file reference
# before smoke phase B runs.
#
# Order matters for diagnosis: run this AFTER smoke phase A (binary/window/GL proof with
# nothing to theme) and BEFORE phase B (list + launch), so a phase-B failure cannot be
# blamed on a missing theme when the theme is already in place.
#
# Three corrections, all from measuring rather than from copying ROCKNIX's recipe (the
# tool that did the measuring is tools/theme/verify/theme-check-local.py, run against the real tree):
#  * the artwork variants are referenced by  <path>./_inc/systems/artwork-noir/...png</path>
#    lines, NOT by  <include name="artwork-noir">  as ROCKNIX's makeinstall assumes for its
#    packaging.  The old sed therefore matched nothing: pruning left 4 missing files and 4
#    references into deleted directories - a theme that errors on load.
#  * so the default here is NOT to prune.  The board has 56 GB free and the set is 288 MB;
#    ROCKNIX prunes to keep a squashfs image small, and we are not shipping a squashfs
#    image out of this tree.  PRUNE=1 opts back in, and then removes every XML line that
#    names a deleted directory (that variant was measured too: 0 dangling).
#  * install with hardlinks (cp -al) instead of a 288 MB copy.  Everything here is on one
#    filesystem, and copying 288 MB onto the SD card that is also compiling is exactly the
#    I/O that made GuiMenu.cpp thrash earlier today.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
PRUNE=${PRUNE:-0}
HERE=$(cd "$(dirname "$0")" && pwd)

# ship the checker so the verification runs against the installed tree, not just the staging copy
timeout 60 sshpass -p $PW scp -o ConnectTimeout=25 "$HERE/theme-check-local.py" root@$DEV:/usr/local/bin/theme-check-local.py >/dev/null 2>&1 \
  || { echo "!! could not push theme-check-local.py"; exit 1; }

timeout 300 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV "PRUNE=$PRUNE sh -s" <<'EOS'
SRC=/root/theme-stage
DST=/root/.emulationstation/themes/art-book-next
echo "  host=$(hostname)  free on /: $(df -h / | awk 'NR==2{print $4}')  build: $(grep -oE '\[ *[0-9]+%\]' /tmp/es-es-build.log 2>/dev/null | tail -1)"
[ -f "$SRC/theme.xml" ] || { echo "  !! $SRC/theme.xml missing - run k72-es-theme-prep.sh first"; exit 1; }

if [ -d "$DST" ]; then
  echo "  already installed: $DST ($(du -sh $DST 2>/dev/null | cut -f1))"
else
  echo "=== installing with hardlinks (no data copy) ==="
  mkdir -p "$DST"
  if cp -al "$SRC"/. "$DST"/ 2>/dev/null; then
    echo "  method: cp -al (same filesystem, nothing rewritten)"
  else
    echo "  cp -al unavailable, falling back to a real copy"
    cp -a "$SRC"/. "$DST"/ || { echo "  !! copy failed"; exit 1; }
  fi
  echo "  installed: $(du -sh $DST | cut -f1), $(find $DST -type f | wc -l) files, artwork variants present: $(ls $DST/_inc/systems | tr '\n' ' ')"
fi

if [ "$PRUNE" = 1 ]; then
  echo "=== PRUNE=1: drop the artwork variants AND every line that names them ==="
  python3 - "$DST" <<'PY'
import os, sys
root = sys.argv[1]
vols = ["artwork-circuit", "artwork-classic", "artwork-nintendont", "artwork-noir", "artwork-outline"]
for v in vols:
    p = os.path.join(root, "_inc", "systems", v)
    if os.path.isdir(p):
        import shutil; shutil.rmtree(p)
        print("  removed dir  %s" % v)
removed_lines = 0
for dirpath, _d, files in os.walk(root):
    for fn in files:
        if not fn.endswith(".xml"):
            continue
        f = os.path.join(dirpath, fn)
        txt = open(f, encoding="utf-8", errors="replace").read().splitlines()
        keep = [l for l in txt if not any("_inc/systems/" + v in l for v in vols)]
        if len(keep) != len(txt):
            open(f, "w", encoding="utf-8").write("\n".join(keep) + "\n")
            removed_lines += len(txt) - len(keep)
            print("  pruned %-46s %3d line(s)" % (os.path.relpath(f, root), len(txt) - len(keep)))
print("  total lines removed: %d   size now: %s" % (removed_lines, os.popen("du -sh %s | cut -f1" % root).read().strip()))
PY
else
  echo "  keeping every artwork variant (default; disk is not the constraint here)"
fi

echo "=== proof: every file reference in the installed tree resolves ==="
python3 /usr/local/bin/theme-check-local.py "$DST" 2>&1 | sed 's/^/  /'

echo
echo "=== point ThemeSet at it (Settings.cpp defaults ThemeSet to \"system-theme\", so"
echo "    installing files alone is NOT enough - ES looks in themes/<ThemeSet>/) ==="
python3 - <<'PY'
import os, re
import xml.etree.ElementTree as ET
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
r = ET.parse(p).getroot()
got = [e.get("value") for e in r if e.get("name") == "ThemeSet"]
print("  es_settings.cfg %s; ThemeSet=%s; root=%s entries=%d" % (action, got, r.tag, len(list(r))))
PY
echo "  note: ES reads es_settings.cfg at startup and rewrites it on exit - if ES is running"
echo "        when this writes, ITS copy wins.  Stop ES first (pkill -f es-app/emulationstation)."
EOS
echo "=== theme install step done ==="
