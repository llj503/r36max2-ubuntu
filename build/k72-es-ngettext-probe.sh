#!/bin/bash
# k72-es-ngettext-probe.sh - before patching the ngettext/pgettext clash, check the
# two things that decide WHERE the patch goes:
#   1. is there a CMake switch that turns HAVE_INTL on (then the fallback branch is
#      never compiled and the "real gettext" path is what upstream ships)?
#   2. where are the fallbacks *defined* - deleting only the declarations in
#      LocaleES.h would leave the definitions behind and break differently.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 120 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
echo "=== HAVE_INTL: who sets it ==="
grep -rn "HAVE_INTL" /root/es/CMakeLists.txt /root/es/es-core/CMakeLists.txt 2>/dev/null | sed 's/^/     /'
echo "  Intl in cache: $(grep -iE '^Intl_|INTL' /root/es/build/CMakeCache.txt 2>/dev/null | head -6 | tr '\n' ' ')"
grep -rn "NLS\|GETTEXT\|Msgfmt\|find_package(Intl" /root/es/CMakeLists.txt 2>/dev/null | head -8 | sed 's/^/     /'
echo
echo "=== where the fallbacks are defined ==="
grep -rn "ngettext\|pgettext" /root/es/es-core/src/LocaleES.cpp 2>/dev/null | head -12 | sed 's/^/     /'
echo "  --- LocaleES.cpp head (guards) ---"
sed -n '1,40p' /root/es/es-core/src/LocaleES.cpp 2>/dev/null | cat -n | sed 's/^/     /'
echo
echo "=== who calls them (must keep compiling) ==="
grep -rln "ngettext\|pgettext" /root/es/es-core/src /root/es/es-app/src 2>/dev/null | head -8 | sed 's/^/     /'
echo "  call sites total: $(grep -rn "ngettext\|pgettext" /root/es/es-core/src /root/es/es-app/src 2>/dev/null | wc -l)"
echo
echo "=== glibc really provides both? (no catalog bound -> identity, same semantics) ==="
grep -nE "extern char \*(n|p)?gettext|extern char \*pgettext" /usr/include/libintl.h | head -6 | sed 's/^/     /'
nm -D --defined-only /usr/lib/aarch64-linux-gnu/libc.so.6 2>/dev/null | grep -E " (ngettext|pgettext)$" | sed 's/^/     libc: /'
EOS
echo "=== probe done ==="
