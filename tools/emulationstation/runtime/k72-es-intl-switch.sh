#!/bin/bash
# k72-es-intl-switch.sh - which of the two fixes is available?  Print the exact
# CMake logic around HAVE_INTL / "Native language support", and prove glibc really
# exports pgettext (if it does not, deleting ES's fallback would break the link
# stage instead of fixing the compile stage - that is the difference between a
# one-line patch and a surprise 25 minutes later).
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 120 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
echo "=== CMake: HAVE_INTL and the NLS switch ==="
grep -n -B4 -A10 "HAVE_INTL" /root/es/CMakeLists.txt /root/es/es-core/CMakeLists.txt 2>/dev/null | head -40 | sed 's/^/  /'
echo "  --- how it decided 'Native language support disabled' ---"
grep -n -B8 "Native language support" /root/es/CMakeLists.txt 2>/dev/null | head -24 | sed 's/^/  /'
echo "  --- option list mentioning language/i18n/nls ---"
grep -niE "option\(.*(lang|i18n|nls|translat)" /root/es/CMakeLists.txt | sed 's/^/     /'
echo
echo "=== is pgettext really in libc (and gettext/ngettext too)? ==="
grep -nE "pgettext|ngettext" /usr/include/libintl.h | head -10 | sed 's/^/     header: /'
for s in gettext ngettext dgettext pgettext dpgettext dcgettext bindtextdomain; do
  if nm -D --defined-only /usr/lib/aarch64-linux-gnu/libc.so.6 2>/dev/null | grep -qE " T $s\$"; then t=yes; else t=NO; fi
  printf "     libc %-16s %s\n" "$s" "$t"
done
echo
echo "=== does the tree carry translations (needed if we turn HAVE_INTL on)? ==="
ls /root/es/Locale 2>/dev/null | head -6 | sed 's/^/     Locale\/: /'
find /root/es -maxdepth 2 -name "*.po" -o -maxdepth 2 -name "*.mo" 2>/dev/null | head -5 | sed 's/^/     /'
echo "  msgfmt available: $(command -v msgfmt || echo NO - HAVE_INTL path would need gettext-tools)"
EOS
echo "=== probe done ==="
