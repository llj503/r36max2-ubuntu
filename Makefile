# 入口只有静态检查。真正的构建要在 WSL/Debian 里交叉编译，
# 步骤见 README 的「从零构建」与「出 v20 的实际顺序」两节。
SHELL := /bin/bash

.PHONY: help lint
help:
	@echo "make lint   语法检查全部脚本，并检查目录约定没被破坏"

lint:
	@bash scripts/lint.sh
