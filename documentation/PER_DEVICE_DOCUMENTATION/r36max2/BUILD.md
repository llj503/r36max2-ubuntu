# 从零构建(v21 构建框架)

[← 返回 README](../../../README.md)

v21 起，构建走 ROCKNIX 式框架：**先自建交叉工具链，再按 package.mk 依赖图构建，最后打包镜像**。
所有外部输入（内核、busybox、joypad 驱动、AIC 驱动、固件、ubuntu-base）都在各自的
`package.mk` 里以 URL + SHA256（或 git/tag ref）锁定，`scripts/get` 下载时强制校验——
pin 抄错一个字符，构建当场失败，而不是把错误的源码编进镜像（这条机制已经真实拦下过一次坏 pin）。

改完东西先跑 `make lint`：语法检查 + 路径约定 + "每个输入必须锁定"的静态断言。CI 跑的就是它。

前置：Ubuntu/Debian 宿主（WSL2 也行），x86_64 宿主交叉编译 arm64。需要
`gcc-aarch64-linux-gnu`（仅作 bootstrap 参考，正式工具链自建）不必预装，跑：

```bash
make checkdeps        # 缺什么装什么；x86_64 宿主会要求 qemu-user-static（chroot arm64 用）
```

三条不变量：

1. **镜像身份不变**：Ubuntu 26.04 base（官方 tarball，SHA256 锁死）+ apt 快照源，
   apt 保留（开发机定位）；自建工具链只编内核/模块/自有 C 程序。
2. **硬件成果不变**：DTS、极性约定、boot.ini 引导链、FAT+ext4 布局、eMMC 不碰。
3. **可复现标准**：输入全部锁定；打包层确定性（固定 UUID、SOURCE_DATE_EPOCH、xz -T1、
   cpio --reproducible）；每版镜像附完整 manifest。apt 底座是"语义可复现"
   （dpkg 清单随镜像发布），字节级一致不承诺——诚实边界。

## 1) 取源（哈希校验）

```bash
make source           # 预取全部输入：内核 7.2.9、busybox、joypad、aic8800、固件、ubuntu-base
```

缓存落在 `sources/<pkg>/`，旁边有 `.sha256`/`.url` 存根。重复跑零下载。

## 2) 工具链 → 项目 → 镜像

```bash
make build toolchain:host   # gmp/mpfr/mpc/binutils/gcc(:host) → build.*/toolchain
                            # gcc 单遍构建：sysroot 由 rootfs-base 包从 ubuntu-base + pinned
                            # -dev deb 填充（这一步不需要 root）
make build image            # 整棵依赖图：内核 7.2.9 + joypad/aic8800 模块 + rootfs 各层 +
                            # 13 个设备包 + gpu-demos + busybox + initramfs
```

`make build image` 里**唯一需要 sudo 的步骤**是 `r36-rootfs-apt`（chroot 里跑 apt），
会提示一次密码。快照时间点写在 `distributions/rk3326/options` 的 `APT_SNAPSHOT`——
升级它是显式、可评审的动作，装完的 dpkg 清单会随镜像发布。

单独重建某一项：

```bash
make kernel                       # 只编内核（Image + 三份 dtb + 模块树）
make build PKG=r36-joypad         # 只编 joypad 模块（自动带上它依赖的内核/工具链）
make build PKG=gpu-demos          # 只编 EGL/GLES2 demo（交叉编译，替代 v20 的预编译 binaries）
```

改动包目录、补丁或 DTS 后重跑同一命令即可：框架按 deep-hash stamp 判断要不要真的重建。

## 3) 打包出镜像

```bash
sudo bash scripts/extract-vendor-blobs.sh /dev/sdX   # 从一张能启动的 ArkOS/EmuELEC 卡 dd 出
                                                     # idbloader/uboot/trust 三块厂商 blob
                                                     # （版权原因不入库，哈希会记录并强校验）
make image                                           # 或只跑打包: bash scripts/image
```

`scripts/image` 保留 v20 `pack-v20.sh` 的全部校验门（vermagic、dtb 极性标志、weston
装而未启、0 个 SSH host key、空 machine-id、无 wpa 凭据），新增：dpkg manifest 在场、
厂商 blob 哈希匹配。任何一项不过**不压缩直接退出**。

确定性措施（v20 → v21 的差异）：固定 FAT volume id / ext4 UUID、rootfs 时间戳钳到
`SOURCE_DATE_EPOCH`（= HEAD 提交时间，可用 `R36_SOURCE_DATE_EPOCH` 覆盖）、
`cpio --reproducible` + 排序输入、`xz -T1`（`-T0` 的输出随宿主核心数变化）。

产物在 `target/`：`.img.xz` + `.sha256` + `.manifest.txt`（输入哈希、工具链版本、
apt 快照、dpkg 计数、产物哈希）。发布时把这三个文件抄进 `distributions/`。

## 关键版本改在哪里

| 要改什么 | 位置 |
| --- | --- |
| 内核版本 | `packages/kernel/linux/package.mk` 的 `PKG_VERSION` + `PKG_SHA256`（kernel.org sha256sums.asc） |
| apt 快照点 | `distributions/rk3326/options` 的 `APT_SNAPSHOT` |
| sysroot 的 -dev 集 | `packages/rk3326/rootfs-base/package.mk` 的 `R36_SYSROOT_DEBS` |
| 设备包集合 | `packages/virtual/image/package.mk` 的 `PKG_DEPENDS_TARGET` |
| 固定 UUID/volid | `distributions/rk3326/options`（改了要在发布记录里写一句） |

## 与 v20 流水线的关系

v20 的 16 步手工脚本（`build-all.sh`、`apply-v19.sh`、`pack-v20.sh`、`v20-*.sh`……）
已被上面这条框架取代，全部删除——git 历史完整，`git log --diff-filter=D --name-only`
能找到它们。设备侧的 ES 真机编译脚本同样删除：ES 已按锁定版本交叉编译进镜像
（见 EMULATIONSTATION.md）。
