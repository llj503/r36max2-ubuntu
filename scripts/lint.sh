#!/bin/bash
# 静态检查整个仓库。不构建镜像：那需要 WSL + aarch64 交叉工具链 + 一块真机。
# 用 make lint 调用（CI 也跑这个）。
#
# 靠 shebang 认脚本，不靠后缀：packages/ 里的 r36-bootlog、r36-es 这些没有后缀，
# 但它们就是要装进 /usr/local/bin 的 shell 脚本。
set -u
cd "$(git rev-parse --show-toplevel)" || exit 1
PYTHON=${PYTHON:-python3}
fail=0

mapfile -t SH < <(git grep -I -l -e '^#!/.*sh' -- .)
mapfile -t PY < <({ git grep -I -l -e '^#!/.*python' -- .; git ls-files '*.py'; } | sort -u)

for f in "${SH[@]}"; do
    bash -n "$f" || { echo "BASH-SYNTAX $f"; fail=1; }
done
for f in "${PY[@]}"; do
    "$PYTHON" -c 'import sys; compile(open(sys.argv[1]).read(), sys.argv[1], "exec")' "$f" ||
        { echo "PYTHON-SYNTAX $f"; fail=1; }
done

# packages/ 里没有后缀的文件必须是带 shebang 的可执行脚本
for f in $(git ls-files -- 'packages/*' | grep -vE '\.[a-zA-Z0-9]+$'); do
    head -c2 "$f" | grep -q '#!' || { echo "NO-SHEBANG $f"; fail=1; }
done

# build/ 只是本机 scratch（第三方源码、CMake 中间产物、wifi-cred.txt），不入库
if [ -n "$(git ls-files -- 'build/*')" ]; then
    echo "ERROR: build/ 下有文件被提交了"; fail=1
fi

echo "lint: $(git ls-files | wc -l) tracked, ${#SH[@]} shell, ${#PY[@]} python"
exit $fail
