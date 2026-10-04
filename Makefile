# 这个仓库的自动化入口。真正的构建要在 WSL/Debian 里交叉编译，
# 步骤见 README 的「从零构建」与「出 v20 的实际顺序」两节 —— 这里只做静态检查。
SHELL := /bin/bash

# 有 sh shebang 的文件（含无扩展名的 packages/r36-*，它们会被装进 /usr/local/bin）
SH = $(shell git grep -I -l -e '^#!/[[:print:]]*sh' -- .)
# 有 python shebang 或 .py 后缀
PY = $(shell git grep -I -l -e '^#!/[[:print:]]*python' -- .; git ls-files '*.py')

.PHONY: help lint
help:
	@echo "make lint   语法检查全部脚本，并检查目录约定没被破坏"

lint:
	@fail=0; \
	for f in $(SH); do bash -n "$$f" || { echo "BASH-SYNTAX $$f"; fail=1; }; done; \
	for f in $(sort $(PY)); do \
	  python3 -c "import sys; compile(open(sys.argv[1]).read(), sys.argv[1], 'exec')" "$$f" \
	    || { echo "PYTHON-SYNTAX $$f"; fail=1; }; \
	done; \
	if [ -n "$$(git ls-files -- 'build/*')" ]; then \
	  echo "ERROR: build/ 只是本机 scratch，不该有文件入库"; fail=1; \
	fi; \
	for f in $$(git ls-files -- 'packages/*' | grep -vE '\.[a-zA-Z0-9]+$$'); do \
	  head -c2 "$$f" | grep -q '#!' || { echo "NO-SHEBANG $$f"; fail=1; }; \
	done; \
	echo "lint: $$(git ls-files | wc -l) tracked, $$(printf '%s\n' $(SH) | wc -l) sh, $$(printf '%s\n' $(PY) | sort -u | wc -l) py"; \
	exit $$fail
