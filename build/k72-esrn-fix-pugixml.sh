#!/bin/bash
# k72-esrn-fix-pugixml.sh - the ROCKNIX build died at 40% on
#   #include <pugixml/src/pugixml.hpp>: No such file or directory
# because I unpacked GitHub's archive tarball, and tarballs do not contain git
# submodules.  Fetch the pinned pugixml (external/.gitmodules -> 61c9448...) and
# rebuild the way a recursive clone would, i.e. with USE_SYSTEM_PUGIXML off.
#
# Also re-arms the temp swap: it had SwapFree=0 kB, which means it is holding stale
# pages from the previous build rather than being available for the next one.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
PUGIXML_SHA=61c944895e071872370219cadade8423dc6e04dc
timeout 420 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV \
  "PUGIXML_SHA=$PUGIXML_SHA sh -s" <<'EOS'
echo "  host=$(hostname)  build dir: $(du -sh /root/esrn 2>/dev/null | cut -f1)"
echo "=== swap housekeeping (it was SwapFree=0) ==="
swapoff /swap.es.img 2>/dev/null; swapon /swap.es.img 2>/dev/null
free -m | awk '/Mem|Swap/{print "     " $0}'

echo "=== fetch the pinned pugixml submodule ==="
cd /root/esrn || exit 1
if [ -f external/pugixml/src/pugixml.hpp ]; then
  echo "     already present"
else
  url=https://github.com/zeux/pugixml/archive/$PUGIXML_SHA.tar.gz
  timeout 180 curl -sSL -o /root/pugixml.tar.gz "$url" || { echo "  !! download failed"; exit 1; }
  rm -rf external/pugixml && mkdir -p external/pugixml
  tar -xzf /root/pugixml.tar.gz -C external/pugixml --strip-components=1 || { echo "  !! extract failed"; exit 1; }
fi
ls external/pugixml/src/pugixml.hpp external/pugixml/CMakeLists.txt 2>/dev/null | sed 's/^/     /'
grep -n "pugixml" .gitmodules | sed 's/^/     gitmodules: /'

echo "=== reconfigure without the system pugixml ==="
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DGLES3=1 -DROCKNIX=1 -DDISABLE_KODI=1 \
      -DENABLE_FILEMANAGER=0 -DCEC=0 -DENABLE_PULSE=0 -DUSE_SYSTEM_PUGIXML=0 -DENABLE_TTS=OFF 2>&1 | tail -8 | sed 's/^/  /'
echo "  cache: $(grep -E '^(GLSystem|USE_SYSTEM_PUGIXML|GLES3)' build/CMakeCache.txt | tr '\n' ' ')"

echo "=== compile the file that failed, as a fast smoke test ==="
timeout 300 cmake --build build --target es-core -j 2 2>&1 | grep -E "pugixml|error:|Building CXX object es-core/CMakeFiles/es-core.dir/src/(AudioManager|SystemConf)" | head -8 | sed 's/^/  /'
echo "  (if no pugixml error above, the include problem is gone)"
EOS
echo "=== then resume the whole build: bash build/k72-esrn.sh build ==="
