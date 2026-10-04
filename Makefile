# r36max2 可复现构建框架（结构对齐 ROCKNIX/distribution）。
# 入口：make checkdeps → make source → make image（= 全量依赖图 + 打包出 .img.xz）。
# 详见 documentation/PER_DEVICE_DOCUMENTATION/r36max2/BUILD.md。
SHELL := /bin/bash

.PHONY: help lint checkdeps source build image kernel clean-%
help:
	@echo "make lint        静态检查（语法、路径约定、输入锁定）— CI 跑这个"
	@echo "make checkdeps   检查/安装宿主依赖（Ubuntu/Debian）"
	@echo "make source      预取全部外部输入并校验 SHA256"
	@echo "make image       构建整棵依赖图并打包 r36max2-ubuntu-<V>.img.xz"
	@echo "make build PKG=<name>[:host|target]   构建单个包"
	@echo "make kernel      只构建内核（Image + dtb + 模块）"

lint:
	@bash scripts/lint.sh

checkdeps:
	@bash scripts/checkdeps

source:
	@bash scripts/get linux
	@bash scripts/get busybox
	@bash scripts/get rocknix-joypad
	@bash scripts/get aic8800
	@bash scripts/get aic8800-dc-fw
	@bash scripts/get rootfs-base
	@bash scripts/get emulationstation
	@bash scripts/get es-theme-art-book-next

build:
	@test -n "$(PKG)" || { echo "usage: make build PKG=<package>"; exit 1; }
	@bash scripts/build $(PKG)

kernel:
	@bash scripts/build linux

image:
	@bash scripts/build image
	@bash scripts/image

clean-%:
	@bash scripts/clean $*
