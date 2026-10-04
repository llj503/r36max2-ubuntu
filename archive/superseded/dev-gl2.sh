#!/bin/bash
# dev-gl2.sh - try to actually run a GL benchmark head-less on the panel, and see
# what the panfrost stack reports.
set -uo pipefail
DEV=${DEV:-192.168.31.209}
S() { sshpass -p ubuntu ssh -o ConnectTimeout=15 root@$DEV "$@" </dev/null 2>/dev/null; }

echo "=== glmark2 变体与显示后端 ==="
S 'dpkg -L glmark2 2>/dev/null | grep -E "bin/" | sed "s/^/  /"
   glmark2 --help 2>&1 | grep -iE "display|use-gles|offscreen" | head -8 | sed "s/^/  /"'

echo "=== 试 glmark2 --display=gbm（会占用面板几秒）==="
S 'timeout 60 glmark2 --display=gbm --benchmark=build:off 2>&1 | tail -22 | sed "s/^/  /" || echo "  gbm backend 不可用"'

echo "=== 若不行：装 dev 头，自己写一个 EGL+GLES2/GBM 的三角形 ==="
S 'export DEBIAN_FRONTEND=noninteractive
   apt-get -y -qq install libgbm-dev libegl-dev libgles-dev libdrm-dev pkg-config >/dev/null 2>&1
   echo "  pkg-config gbm: $(pkg-config --modversion gbm 2>/dev/null)"
   echo "  pkg-config egl: $(pkg-config --modversion egl 2>/dev/null)"
   echo "  pkg-config glesv2: $(pkg-config --modversion glesv2 2>/dev/null)"'
