#!/bin/bash
# k72-es-locale.sh - the two things needed to fix the ngettext clash properly:
# the guard around LocaleES.h's declarations, and glibc's own prototype as the
# compiler saw it ("previous declaration" note).  Patching the wrong side of this
# (glibc's header vs ES's header, or deleting the declaration instead of matching
# the signature) is what turns a one-line fix into a hunt.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 120 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
echo "=== LocaleES.h lines 1-26 ==="
sed -n '1,26p' /root/es/es-core/src/LocaleES.h | cat -n | sed 's/^/  /'
echo
echo "=== the raw error + notes from the log ==="
grep -n -A22 "ambiguating new declaration" /tmp/es-build.log 2>/dev/null | head -34 | sed 's/^/  /'
echo
echo "=== glibc's prototypes as installed ==="
grep -nE "extern (char|const char) \*(ngettext|pgettext|dgettext|gettext)" /usr/include/libintl.h | sed 's/^/     /'
echo
echo "=== does this build define ENABLE_NLS anywhere? ==="
grep -rn "ENABLE_NLS" /root/es/build/CMakeCache.txt /root/es/es-core/CMakeLists.txt /root/es/CMakeLists.txt 2>/dev/null | head -6 | sed 's/^/     /'
grep -rn "ENABLE_NLS\|WITH_I18N\|NLS" /root/es/build/CMakeFiles/es-core.dir/flags.make 2>/dev/null | head -4 | sed 's/^/     flags: /'
echo "  (if ENABLE_NLS is absent, LocaleES.h's stub declarations are the ones in play)"
EOS
echo "=== locale context done ==="
