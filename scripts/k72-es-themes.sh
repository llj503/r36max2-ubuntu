#!/bin/bash
# k72-es-themes.sh - where does this ES build expect themes, and what happens when
# none are installed?  ES-CE bundles resources (fonts/svg) but the *themes* come from
# separate packages in Batocera/ROCKNIX, so a first launch on plain Ubuntu may find no
# theme at all.  Read it out of the source instead of guessing, and record what
# Settings::getInstance() would use by default (the k72-es-smoke.sh log will confirm
# within seconds whether ES exits on it).
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 150 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
echo "  host=$(hostname)  progress=$(grep -oE '\[ *[0-9]+%\]' /tmp/esrn-build.log 2>/dev/null | tail -1)"
echo "=== theme search paths the code actually uses ==="
grep -rhoE '"[^"]*themes[^"]*"' /root/esrn/es-core/src /root/esrn/es-app/src 2>/dev/null | sort -u | head -12 | sed 's/^/     /'
echo
echo "=== default theme name / fallback ==="
grep -rnE 'DEFAULT_THEME|setDefaults|"es2-|getThemeName' /root/esrn/es-core/src/Settings.cpp 2>/dev/null | head -8 | sed 's/^/     /'
echo
echo "=== is there a built-in fallback renderer when no theme is found? ==="
grep -rnE 'throw|ES_FATAL|could not (load|find) theme|No theme' /root/esrn/es-core/src/ThemeData.cpp /root/esrn/es-app/src/Window.cpp 2>/dev/null | head -8 | sed 's/^/     /'
echo
echo "=== what exists on disk right now ==="
for d in /usr/share/emulationstation /etc/emulationstation /root/.emulationstation /root/esrn/resources; do
  echo "     $d : $(ls "$d" 2>/dev/null | wc -l) entries$(ls -d "$d/themes" 2>/dev/null | sed 's/.*/ + themes\//')"
done
echo
echo "=== what Batocera installs besides the binary (theme packages) ==="
for p in batocera-es-system es-theme; do
  echo "     grep '$p':"; done
grep -rn "themes" /root/esrn/THEMES.md 2>/dev/null | head -6 | sed 's/^/     THEMES.md: /'
EOS
echo "=== theme probe done ==="
