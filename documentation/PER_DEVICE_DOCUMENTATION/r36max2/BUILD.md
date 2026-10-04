# 从零构建

[← 返回 README](../../../README.md)

改完东西先跑 `make lint`（等价于 `bash scripts/lint.sh`）：按 shebang 找出所有 shell
与 python 脚本做语法检查，并确认没有文件被放回 `build/`。GitHub Actions 跑的就是它。

前置：WSL2 Ubuntu（或任意能交叉编译的 Debian 系），需要
`gcc-aarch64-linux-gnu device-tree-compiler rsync xz-utils squashfs-tools u-boot-tools sshpass`。

v20 是**双内核镜像**，所以两棵树都要先编出来：7.2.8 是默认启动项，6.12.79 留在同一张卡上
作为"改一个文件名就退回去"的保险（`pack-v20.sh` 里写死 `K6=/root/r36/linux-6.12.79`，
两棵模块树、`boot-612.ini` 都从它取）。6.12.79 不是遗留支线，是当前镜像的构建输入。

## 1) 两棵内核树

```bash
sudo mkdir -p /root/r36 && cd /root/r36
# 6.12.79：linux-6.12.79 + Rocknix 的三层补丁（mainline → devices/RK3326 → 6.12-LTS）
tar xf linux-6.12.79.tar.xz
cp projects/r36max2/dt/rk3326-xifan-r36max2*.dts* linux-6.12.79/arch/arm64/boot/dts/rockchip/
#    并在该目录 Makefile 的 dtb-$(CONFIG_ARCH_ROCKCHIP) 里加一行
bash scripts/apply-mainline.sh
bash scripts/build-all.sh                                      # K 默认就是 linux-6.12.79
K=/root/r36/linux-7.2.8 bash scripts/build-all.sh              # 7.2.8：16 核 505 秒
```

`build-all.sh` 一并编两个外部模块（rocknix joypad、AIC8800DC WiFi）。7.2.8 那棵树需要先
`bash scripts/k72-prepare.sh`（搬 `panel-generic-dsi.c` 进主线并挂 Kconfig），补丁层的
处理方式见 [KERNELS.md](KERNELS.md)。

## 2) rootfs 与 initramfs

```bash
bash scripts/build-rootfs.sh     # ubuntu-base 解包 → apt 装包 → 写配置
                                 # WiFi 凭据从 build/wifi-cred.txt 读；发布用镜像请置 R36_BAKE_WIFI=0
bash scripts/apply-v19.sh        # 把真机上验证过的改动回写进 rootfs（幂等，可重复跑）
bash scripts/build-initrd3.sh    # busybox initramfs，按 marker 文件找根分区
```

## 3) 出 v20 的实际顺序

v20 不是"再跑一遍老脚本"，它把 7.2.8、gpiod 摇杆、WiFi 兼容补丁和图形栈一起收进来，
所以顺序和检查点都记在 `scripts/v20-*.sh` 里，按编号执行：

```bash
bash scripts/v20-stage72.sh      # 7.2.8 的 Image / 三份 dtb 落到 out/boot，核对 dtb 里的 gpio 极性标志
bash scripts/v20-aic72b.sh       # 干净的 AIC 源码副本 + 7.2.8 兼容补丁 -> 对 7.2.8 重编 -> 与卡上正在用的 .ko 比 sha
bash scripts/v20-rootfs.sh       # 两个内核的模块树进 rootfs，逐个 modinfo 断言 vermagic，chroot 里 depmod + modprobe -n
bash scripts/apply-v19.sh        # 把真机验证过的改动回写（幂等，可重复跑）
bash scripts/v20-clean-wpa.sh    # 删掉被 mask 单元的残留 wants 软链（masked+enabled 会在开机报错）
python3 scripts/v20-hostkeys.py  # 扫凭据 + 把镜像里的 SSH 主机密钥换成首次开机现生成
bash scripts/apply-wayland.sh    # weston/foot/wofi/grim/wf-recorder/kbd + weston.ini/service + 键鼠桥（不 enable）
bash scripts/v20-tidy.sh         # apt cache / lists / 大日志清掉，量一下要塞进 2 GiB 分区的内容
V=v20 bash scripts/pack-v20.sh   # 打包：MBR + 三个厂商 blob + FAT(BOOT) + ext4(2 GiB) → .img.xz，压缩前自检
```

`pack-v20.sh` 需要三个厂商 blob（`idbloader.img` / `uboot.img` / `trust.img`），从一张能启动的
ArkOS/EmuELEC 卡上 dd 出来即可（偏移 32 KiB / 8 MiB / 12 MiB）；因为版权原因本仓库不分发它们，
也不分发 EmuELEC 的 dtb。

`pack-v20.sh` 的自检不是装饰：它挂载镜像后逐项核对**两个内核各自的 .ko 数量、
extra 模块的 vermagic 与内核版本一致**（放错内核的模块不会报错，只会让 WiFi 和按键
神秘消失）、dtb 里 `amux-a/amux-en/rumble` 的极性标志、weston **存在但没有被 enable**、
镜像里 **0 个 SSH 主机密钥** 且首次开机生成单元到位、`machine-id` 为空、没有任何
wpa 凭据文件、`build`/`source` 软链接已删除；任何一项不过就**不压缩**、直接退出。

两处与"给别人用"相关的安全改动，v20 起才成立：**镜像不带 WiFi 凭据**（靠
`BOOT:\wifi.txt` 配网，见 [WIFI-AND-SHARING.md](WIFI-AND-SHARING.md)），**镜像不带 SSH 主机密钥**（`r36-hostkeys.service`
在首次开机 `ssh-keygen -A`，`ssh.service` 加 drop-in 依赖它，否则 sshd 起不来）。
默认账号密码仍是 `ubuntu`/`ubuntu`，[FLASH.md](FLASH.md) 与 `r36-switches.txt` 都写了刷机后第一件事是 `passwd`（另见 [SECURITY.md](SECURITY.md)）。

## 更早的版本

v19 及以前的打包流程（`build-image*.sh`、`apply-v11..v17.sh`、v19 那版打包器）已经不在仓库里
—— 它们被上面这条 v20 流程取代了。需要时用 `git log --diff-filter=D --name-only` 找到删除它们
的那次提交，再从那次提交的父提交里取回文件。
