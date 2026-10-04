# 从零构建(v21 构建框架)

[← 返回 README](../../../README.md)

v21 起，构建走 ROCKNIX 式框架：**先自建交叉工具链，再按 package.mk 依赖图构建，最后打包镜像**。
所有外部输入（内核、busybox、joypad 驱动、AIC 驱动、固件、ubuntu-base）都在各自的
`package.mk` 里以 URL + SHA256（或 git/tag ref）锁定，`scripts/get` 下载时强制校验——
pin 抄错一个字符，构建当场失败，而不是把错误的源码编进镜像（这条机制已经真实拦下过一次坏 pin）。

改完东西先跑 `make lint`：语法检查 + 路径约定 + "每个输入必须锁定"的静态断言。CI 跑的就是它。

<<<<<<< HEAD
前置：Ubuntu/Debian 宿主（WSL2 也行），x86_64 宿主交叉编译 arm64。需要
`gcc-aarch64-linux-gnu`（仅作 bootstrap 参考，正式工具链自建）不必预装，跑：

```bash
make checkdeps        # 缺什么装什么；x86_64 宿主会要求 qemu-user-static（chroot arm64 用）
```

三条不变量：
=======
v21 是**单内核镜像**：只编 7.2.8，只装 7.2.8 的模块树。6.12.79 以前作为回退保险整套装在卡上，
现在那条路只留在 git 历史里（原因见 [KERNELS.md](KERNELS.md) 开头）。

## 1) 内核树

```bash
sudo mkdir -p /root/r36 && cd /root/r36
tar xf linux-7.2.8.tar.xz
bash scripts/k72-prepare.sh                                  # 搬 panel-generic-dsi.c + 挂 Kconfig + 装我们的 dts
K=/root/r36/linux-7.2.8 OUT=/root/r36/out72 bash scripts/build-all.sh   # 16 核 505 秒
```

`build-all.sh` 一并编两个外部模块（rocknix joypad、AIC8800DC WiFi）。补丁层的处理方式见
[KERNELS.md](KERNELS.md)。

> 外部模块现在**不**从这棵构建树进镜像：`scripts/v20-rootfs.sh` 只认
> `artifacts/prebuilt/` 里在卡上实测过的那四份 `.ko`，并且逐个校 `MANIFEST.sha256` 与
> vermagic。原因见下面"自检"一节。
>>>>>>> origin/main

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

<<<<<<< HEAD
缓存落在 `sources/<pkg>/`，旁边有 `.sha256`/`.url` 存根。重复跑零下载。

## 2) 工具链 → 项目 → 镜像

```bash
make build toolchain:host   # gmp/mpfr/mpc/binutils/gcc(:host) → build.*/toolchain
                            # gcc 单遍构建：sysroot 由 rootfs-base 包从 ubuntu-base + pinned
                            # -dev deb 填充（这一步不需要 root）
make build image            # 整棵依赖图：内核 7.2.9 + joypad/aic8800 模块 + rootfs 各层 +
                            # 13 个设备包 + gpu-demos + busybox + initramfs
=======
## 3) 出 v21 的实际顺序

v20 把 7.2.8、gpiod 摇杆、WiFi 兼容补丁和图形栈一起收进来，v21 再收进 ES 并把
双内核退成单内核，所以顺序和检查点都记在 `scripts/v20-*.sh` 里，按编号执行：

```bash
bash scripts/v20-stage72.sh      # 7.2.8 的 Image / 三份 dtb 落到 out/boot，核对 dtb 里的 gpio 极性标志
bash scripts/v20-aic72b.sh       # 干净的 AIC 源码副本 + 7.2.8 兼容补丁 -> 对 7.2.8 重编 -> 与卡上正在用的 .ko 比 sha
bash scripts/v20-rootfs.sh       # 7.2.8 模块树进 rootfs；extra/ 只从 artifacts/prebuilt 取，逐个校 sha256 + vermagic
bash scripts/apply-v19.sh        # 把真机验证过的改动回写（幂等，可重复跑）
bash scripts/v20-clean-wpa.sh    # 删掉被 mask 单元的残留 wants 软链（masked+enabled 会在开机报错）
python3 scripts/v20-hostkeys.py  # 扫凭据 + 把镜像里的 SSH 主机密钥换成首次开机现生成
bash scripts/apply-wayland.sh    # weston/foot/wofi/grim/wf-recorder/kbd + weston.ini/service + 键鼠桥（不 enable）
bash scripts/apply-es.sh         # ES 启动器 + es_input/es_systems + 二进制与主题（从 artifacts/es 取，校 SHA256SUMS）
bash scripts/v20-tidy.sh         # apt cache / lists / 大日志清掉，量一下要塞进 2 GiB 分区的内容
V=v21 bash scripts/pack-v20.sh   # 打包：MBR + 三个厂商 blob + FAT(BOOT) + ext4(2 GiB) → .img.xz，压缩前自检
>>>>>>> origin/main
```

`make build image` 里**唯一需要 sudo 的步骤**是 `r36-rootfs-apt`（chroot 里跑 apt），
会提示一次密码。快照时间点写在 `distributions/rk3326/options` 的 `APT_SNAPSHOT`——
升级它是显式、可评审的动作，装完的 dpkg 清单会随镜像发布。

<<<<<<< HEAD
单独重建某一项：

```bash
make kernel                       # 只编内核（Image + 三份 dtb + 模块树）
make build PKG=r36-joypad         # 只编 joypad 模块（自动带上它依赖的内核/工具链）
make build PKG=gpu-demos          # 只编 EGL/GLES2 demo（交叉编译，替代 v20 的预编译 binaries）
```
=======
两块**不进仓库的暂存目录**，缺了就直接失败、不会出一个"看起来完整"的镜像：

- `artifacts/prebuilt/`：卡上实测过的四份 `.ko` + `MANIFEST.sha256`（`v20-rootfs.sh` 用）。
- `artifacts/es/`：板子上那份 `emulationstation` 二进制、`art-book-next` 主题 + `SHA256SUMS`
  （`apply-es.sh` 用）。取回的方式是 `DEV=192.168.0.141 bash scripts/fetch-card-artifacts.sh`：
  先在**卡上**算好每个文件的 sha256，rsync 拉下来（约 400 MB，2.4G WiFi 上一趟 4 分钟），
  再逐个用卡上那份哈希校我们这份 —— 对不上就直接失败，不写 SHA256SUMS。全程只读卡。
  ES 不是这条流水线编出来的，所以它和 `.ko` 一样按"取回已验证的字节"处理，而不是按
  "装上就算"处理。2026-10-04 拉回来的结果：二进制 117,246,560 B / sha `7bc65872…`，
  主题 1612 个文件全部与卡上逐字节一致，`file` 确认是 ELF aarch64（带 debug_info、未 strip）。
- 体积要盯：ES 二进制 + 主题 = **399 MB**，而 root 分区只有 2 GiB。要瘦身就按
  `scripts/k72-es-theme-install.sh` 里量过的 `PRUNE=1`（剪掉没用到的 artwork 变体，实测
  0 处悬空引用），别动二进制 —— 一 strip 就和卡上验过的那份不是同一串字节了。
- `apply-es.sh` 写的 `es_settings.cfg` 只有 `ThemeSet`；卡上那份还有 `Language=zh_CN`、
  `LastSystem=favorites`、`ShowFlags/ShowTags=auto`。中文界面要不要进镜像是没定过的事，
  别让它在镜像和卡之间悄悄漂移。

`pack-v20.sh` 的自检不是装饰：它挂载镜像后逐项核对**镜像里只有一棵模块树（7.2.8）**、
**`extra` 里四个模块的 vermagic 与 `MANIFEST.sha256` 的 sha 都对得上**、**每个 `boot*.ini` 与
`extlinux.conf` 点名的文件真的在 FAT 分区上**、dtb 里 `amux-a/amux-en/rumble` 的极性标志、
weston **存在但没有被 enable**、wifi-setup 的 service 与 timer **都在 `.wants/` 里**（v20 那张卡
就是因为单元没装才连不上网，而 `r36-boot.txt` 的服务清单里根本没有它，所以"日志里没提"什么都
不证明）、ES 的启动器 + 二进制 + 两份 cfg 都在且 `es_input.cfg` 保留本板 GUID 与两根摇杆轴、
镜像里 **0 个 SSH 主机密钥** 且首次开机生成单元到位、`machine-id` 为空、没有明文 WiFi 口令、
`build`/`source` 软链接已删除；任何一项不过就**不压缩**、直接退出。

两处与"给别人用"相关的安全改动，v20 起才成立：**默认镜像不带 WiFi 凭据**（靠
`BOOT:\wifi.txt` 配网，见 [WIFI-AND-SHARING.md](WIFI-AND-SHARING.md)），**镜像不带 SSH 主机密钥**（`r36-hostkeys.service`
在首次开机 `ssh-keygen -A`，`ssh.service` 加 drop-in 依赖它，否则 sshd 起不来）。
开发时想省配网步骤可以 `R36_BAKE_WIFI=1`，那时烤进去的也是 PBKDF2 哈希不是明文口令，
而卡上的 `r36-switches.txt` 会自动多写一行说明这张卡带着凭据。
默认账号密码仍是 `ubuntu`/`ubuntu`（root 同样是），[FLASH.md](FLASH.md) 与 `r36-switches.txt`
都写了刷机后第一件事是 `passwd`（另见 [SECURITY.md](SECURITY.md)）。
>>>>>>> origin/main

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
