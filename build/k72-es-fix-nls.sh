#!/bin/bash
# k72-es-fix-nls.sh - fix the ngettext clash the way upstream intends, not by
# patching source.
#
# CMake only defines HAVE_INTL when msgfmt + msgmerge + xgettext + Intl are all
# present (CMakeLists.txt:534-544).  Without it, LocaleES.h declares its own
#   const char* ngettext(const char*, const char*, unsigned long int)
# which is ill-formed against glibc's extern "C" char* ngettext(...) - and on
# Ubuntu 26.04 <libintl.h> now arrives through <iomanip> -> <locale> ->
# bits/messages_members.h (a libstdc++ 15 change), so it breaks where it used to
# compile.  Installing gettext turns HAVE_INTL on: the fallback branch disappears
# and ES's bundled GNU gettext.h supplies pgettext (this glibc has no pgettext).
#
# Deleting the fallback instead would NOT work: pgettext really is absent here.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 420 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
echo "  host=$(hostname)"
echo "=== [1] install gettext (msgfmt/msgmerge/xgettext) ==="
DEBIAN_FRONTEND=noninteractive apt-get install -y -q gettext 2>&1 | tail -4
for t in msgfmt msgmerge xgettext; do printf "  %-10s %s\n" "$t" "$(command -v $t || echo MISSING)"; done

echo "=== [2] reconfigure and prove HAVE_INTL is on ==="
cd /root/es || exit 1
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DGL=ON -DCEC=OFF -DBATOCERA=OFF \
      -DUSE_SYSTEM_PUGIXML=ON -DENABLE_TTS=OFF -DENABLE_FILEMANAGER=OFF 2>&1 | grep -iE "language|Intl|Graphics API|error" | sed 's/^/  /'
echo "  HAVE_INTL in the compile flags: $(grep -ro 'DHAVE_INTL' build/es-core/CMakeFiles/es-core.dir/flags.make 2>/dev/null | head -1 || echo NOT-FOUND)"
grep -q HAVE_INTL build/es-core/CMakeFiles/es-core.dir/flags.make 2>/dev/null \
  && echo "  => fallback branch will not be compiled; resume the build" \
  || echo "  !! still no HAVE_INTL - do not resume, look again"
echo "  GLSystem still: $(grep '^GLSystem' build/CMakeCache.txt)"
EOS
echo "=== then: bash build/k72-es-build.sh ==="
