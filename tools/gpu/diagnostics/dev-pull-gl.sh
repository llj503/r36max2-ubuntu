#!/bin/bash
# dev-pull-gl.sh - copy the on-device GPU demo sources + built binaries back to
# the Windows side so apply-v19.sh can bake them into the image.
set -uo pipefail
DEV=${DEV:-192.168.31.209}
D=/mnt/e/ubuntu/artifacts/gl
mkdir -p "$D"
for f in r36-gles2-demo r36-gles2-demo.c egl-probe egl-probe.c; do
  if sshpass -p ubuntu scp -q "$DEV:/root/$f" "$D/$f" 2>/dev/null </dev/null; then
    echo "  got $f"
  else
    echo "  MISSING $f"
  fi
done
ls -l "$D"
command -v file >/dev/null && file "$D"/* 2>/dev/null | sed 's/^/  /'
sha256sum "$D"/* | sed 's|/mnt/e/ubuntu/artifacts/gl/||'
