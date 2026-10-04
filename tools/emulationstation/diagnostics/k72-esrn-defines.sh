#!/bin/bash
# k72-esrn-defines.sh - confirm which GL backend the ROCKNIX build will actually
# compile.  The CMake cache says GLSystem=OpenGL ES 3.0, but that is only a cache
# string: what matters is the -D flags handed to the compiler and the #ifdefs in the
# renderer sources.  Checking now costs one command; discovering it after a 50 minute
# build costs an evening.
set -uo pipefail
PW=ubuntu
DEV=${DEV:-192.168.31.209}
timeout 120 sshpass -p $PW ssh -o ConnectTimeout=25 root@$DEV 'sh -s' <<'EOS'
echo "  host=$(hostname)"
echo "=== where are the flags files ==="
find /root/esrn/build -name flags.make 2>/dev/null | head -5 | sed 's/^/     /'
f=$(find /root/esrn/build -path '*es-core*' -name flags.make 2>/dev/null | head -1)
echo "  using: ${f:-none}"
if [ -n "$f" ]; then
  echo "=== -D defines handed to es-core ==="
  tr ' ' '\n' < "$f" | grep -E '^[-]D' | sed 's/^/     /'
fi
echo
echo "=== how CMake turns GLSystem into defines ==="
grep -n -A6 'GLSystem' /root/esrn/CMakeLists.txt 2>/dev/null | grep -E "add_definitions|MATCHES|GLSYSTEM|GLES" | head -14 | sed 's/^/     /'
echo
echo "=== what the renderer sources test ==="
grep -rnoE "defined\(GLES[0-9]?\)|ifdef GLES[0-9]?|ifndef GLES[0-9]?|GL_GLEXT|GL/gl\.h|GLES[0-9]?/gl[0-9]?.h" \
  /root/esrn/es-core/src/renderer/*.h /root/esrn/es-core/src/Renderer.h 2>/dev/null | head -12 | sed 's/^/     /'
echo
echo "=== is a desktop-GL-only symbol going to bite us? (glew / glCoreArk) ==="
grep -rlE "GL/glew|gl3w|GLAD" /root/esrn/es-core/src 2>/dev/null | head -5 | sed 's/^/     uses GL loader: /'
echo "  GLES headers available: $(ls /usr/include/GLES2 /usr/include/GLES3 2>/dev/null | tr '\n' ' ')"
EOS
echo "=== defines check done ==="
