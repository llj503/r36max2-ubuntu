#!/bin/bash
# k72-es-error.sh - show one compile error with enough context to fix it properly:
# the full diagnostic (including glibc's "previous declaration" note), the offending
# header, and who includes libintl.h.  Guessing at this from a one-line tail is how
# you end up patching the wrong file.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
PAT=${PAT:-LocaleES}
timeout 120 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV "PAT=$PAT sh -s" <<'EOS'
echo "=== full diagnostic around '$PAT' ==="
grep -n -A12 -B6 "error:" /tmp/es-build.log 2>/dev/null | grep -A18 -B6 "$PAT" | head -60 | sed 's/^/  /'
echo
echo "=== es-core/src/LocaleES.h ==="
cat -n /root/es/es-core/src/LocaleES.h 2>/dev/null | head -60 | sed 's/^/  /'
echo
echo "=== who is responsible for the glibc declaration? ==="
grep -rn "libintl.h" /root/es/es-core/src/ 2>/dev/null | head -8 | sed 's/^/     /'
grep -rn "ENABLE_GETTEXT\|HAVE_I18N\|NATIVE_LANGUAGE" /root/es/es-core/src/LocaleES.h /root/es/es-core/CMakeLists.txt 2>/dev/null | head -10 | sed 's/^/     /'
echo "  glibc ngettext prototype:"
grep -n -A3 "extern const char \*ngettext" /usr/include/libintl.h 2>/dev/null | head -8 | sed 's/^/     /'
echo
echo "=== how far did we get / what is left ==="
grep -oE '\[ *[0-9]+%\]' /tmp/es-build.log | tail -1 | sed 's/^/  progress: /'
grep -c "error:" /tmp/es-build.log | sed 's/^/  errors: /'
pgrep -c -f 'cc1plus' | sed 's/^/  still compiling: /'
EOS
echo "=== error context done ==="
