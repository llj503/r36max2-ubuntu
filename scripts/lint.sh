#!/bin/bash
# 静态检查整个仓库。不构建镜像：那需要交叉编译 + 厂商 blob + 一块真机。
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

# packages/ 里没有后缀的文件必须是带 shebang 的可执行脚本（Makefile 除外）
for f in $(git ls-files -- 'packages/*' | grep -vE '\.[a-zA-Z0-9]+$' | grep -v '/Makefile$'); do
    head -c2 "$f" | grep -q '#!' || { echo "NO-SHEBANG $f"; fail=1; }
done

# build/、sources/（下载缓存）只是本机 scratch，不入库
for d in 'build/*' 'sources/*' 'target/*' 'build.*'; do
    if [ -n "$(git ls-files -- "$d")" ]; then
        echo "ERROR: $d 下有文件被提交了"; fail=1
    fi
done

# v21 可复现构建的两条铁律：
# 1) 构建脚本不得指向作者旧机器的路径（旧构建盘符 + 旧 scratch 目录，
#    字面量拼出来以免这条规则匹配到它自己）
BAD1="/mnt/"e/
BAD2="/root/"r36
for f in $(git ls-files -- 'scripts/*' 'packages/*/package.mk' 'packages/*/*/package.mk'); do
    if grep -qE "${BAD1}|${BAD2}" "$f"; then
        echo "HARDCODED-PATH $f（v21 起路径一律来自 config/path）"; fail=1
    fi
done
# 2) 每个外部输入必须锁定：要么 PKG_SHA256，要么 PKG_URL=""（仓库内源码）；
#    virtual 元包只有依赖没有源码，豁免
for f in $(git ls-files -- '*package.mk'); do
    grep -q '^PKG_NAME=' "$f" || continue
    grep -q '^PKG_SECTION="virtual"' "$f" && continue
    if ! grep -q '^PKG_SHA256=' "$f" && ! grep -q '^PKG_URL=""' "$f"; then
        echo "UNPINNED-SOURCE $f（需要 PKG_SHA256 或 PKG_URL=\"\"）"; fail=1
    fi
    bash -n "$f" || { echo "PACKAGE.MK-SYNTAX $f"; fail=1; }
done
# 3) 目录名必须等于 PKG_NAME。scripts/build / scripts/unpack 用「依赖名」找目录，
#    而 source 完 package.mk 之后 PKG_NAME 会被配方自己的值覆盖，两跳之间不一致
#    就会去找一个不存在的目录 —— v21 第一次跑到 bootlog 就是这个错：
#    "unable to source package - r36-bootlog/package.mk does not exist"。
for f in $(git ls-files -- '*package.mk'); do
    grep -q '^PKG_NAME=' "$f" || continue
    d=$(basename "$(dirname "$f")")
    n=$(sed -n 's/^PKG_NAME="\([^"]*\)"/\1/p' "$f" | head -1)
    [ "$d" = "$n" ] || { echo "PKG-NAME-MISMATCH $f：目录=$d 但 PKG_NAME=$n"; fail=1; }
done
# 4) 依赖名必须指向一个真实的包目录。v21 第一次跑到 wayland 时报
#    "unable to source package - r36-keymapper/package.mk does not exist"：
#    依赖写的是旧的 PKG_NAME，而框架按目录名找包。
#    依赖行可以用 \ 续行，也要剥掉 :host / :target / :init 这类变体后缀。
PKGS=$(for d in $(git ls-files -- '*package.mk'); do basename "$(dirname "$d")"; done | sort -u)
for f in $(git ls-files -- '*package.mk'); do
    joined=$(sed -e :a -e '/\\$/N; s/\\\n//; ta' "$f")
    for line in $(echo "$joined" | grep -E '^PKG_DEPENDS_(TARGET|HOST|INIT)=' | sed 's/^[^=]*=//'); do
        for p in $(echo "$line" | tr -d '"'); do
            [ -z "${p%%:*}" ] && continue
            echo "$PKGS" | grep -qx "${p%%:*}" && continue
            echo "UNKNOWN-DEP $f：依赖 $p 没有对应的包目录"; fail=1
        done
    done
done

echo "lint: $(git ls-files | wc -l) tracked, ${#SH[@]} shell, ${#PY[@]} python"
exit $fail
