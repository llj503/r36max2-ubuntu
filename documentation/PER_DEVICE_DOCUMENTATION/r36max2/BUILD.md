# 从零构建（v21 构建框架）

[← 返回 README](../../../README.md)

v21 起，构建走 ROCKNIX 式框架：**先自建交叉工具链，再按 package.mk 依赖图构建，最后打包镜像**。
所有外部输入（内核、busybox、joypad 驱动、AIC 驱动、固件、ubuntu-base）都在各自的 `package.mk`
里以 URL + SHA256（或 git/tag ref）锁定，`scripts/get` 下载时强制校验 —— pin 抄错一个字符，
构建当场失败，而不是把错误的源码编进镜像（这条机制已经真实拦下过一次坏 pin）。

改完东西先跑 `make lint`：语法检查 + 路径约定 + "每个输入必须锁定"的静态断言。CI 跑的就是它。

三条不变量：

1. **镜像身份不变**：Ubuntu 26.04 base（官方 tarball，SHA256 锁死）+ apt 快照源，
   apt 保留（开发机定位）；自建工具链只编内核/模块/自有 C 程序。
2. **硬件成果不变**：DTS、极性约定、boot.ini 引导链、FAT+ext4 布局、eMMC 不碰。
3. **可复现标准**：输入全部锁定；打包层确定性（固定 UUID、SOURCE_DATE_EPOCH、xz -T1、
   cpio --reproducible）；每版镜像附完整 manifest。apt 底座是"语义可复现"
   （dpkg 清单随镜像发布），字节级一致不承诺 —— 诚实边界。

## 0) 前置：宿主必须能执行 arm64

```bash
make checkdeps        # 缺什么装什么；x86_64 宿主会要求 qemu-user-static（chroot arm64 用）
```

这是真踩过的坑，不是理论问题：`rootfs-apt` 要在 chroot 里跑 `dpkg -i`，而 arm64 的二进制在
x86_64 宿主上要靠内核的 binfmt 规则。**规则写在 `/proc/sys/fs/binfmt_misc` 里，是运行时状态，
WSL 空闲超时把 VM 停掉就没了**。2026-10-04 那次就是这样：chroot 全部 `Exec format error`，
apt 一个包都没装，但脚本照样把配置写完并打印了 `ROOTFS BUILD DONE`。

现在 `packages/rk3326/rootfs-apt/package.mk` 在 chroot 之前先调
`bash scripts/require-arm64.sh <rootfs>`：没有处理器就按 qemu 包里自带的规则
（`/usr/lib/binfmt.d/qemu-aarch64.conf`）注册；注册完立刻验证宿主自己的二进制还能跑。
**不要手写这条规则**：我手写过一次，`\x7fELF` 被 bash 的 printf 吞掉一个十六进制位，
结果连 `/usr/bin/ls` 都被交给 qemu 执行，整个 WSL 立刻不可用，只能 `wsl --shutdown` 才救回来。
`scripts/register-binfmt-aarch64.sh` 会把解码后的 magic 打印出来，并断言 e_machine 是 `b7 00`
（aarch64）、掩码确实锁住了 e_machine，就是这个原因。

## 1) 取源（哈希校验）

```bash
make source           # 预取全部输入：内核 7.2.9、busybox、joypad、aic8800、固件、ubuntu-base
```

缓存落在 `sources/<pkg>/`，旁边有 `.sha256`/`.url` 存根。重复跑零下载。

## 2) 工具链 → 项目 → 镜像

```bash
make build PKG=toolchain:host  # gmp/mpfr/mpc/binutils/gcc(:host) → build.*/toolchain
                               # gcc 单遍构建：sysroot 由 rootfs-base 包从 ubuntu-base + pinned
                               # -dev deb 填充（这一步不需要 root）
make build PKG=image           # 整棵依赖图：内核 7.2.9 + joypad/aic8800 模块 + rootfs 各层 +
                               # 设备包 + gpu-demos + busybox + initramfs
```

`make build PKG=image` 里**唯一需要 sudo 的步骤**是 `rootfs-apt`（chroot 里跑 apt），会提示一次
密码。快照时间点写在 `distributions/rk3326/options` 的 `APT_SNAPSHOT` —— 升级它是显式、可评审
的动作，装完的 dpkg 清单会随镜像发布。

改动包目录、补丁或 DTS 后重跑同一命令即可：框架按 deep-hash stamp 判断要不要真的重建。

单独重建某一项：

```bash
make build PKG=linux              # 只编内核（Image + 三份 dtb + 模块树）
make build PKG=rocknix-joypad     # 只编 joypad 模块（自动带上它依赖的内核/工具链）
make build PKG=gpu-demos          # 只编 EGL/GLES2 demo（交叉编译，替代 v20 的预编译 binaries）
make build PKG=emulationstation   # 只编 ES
```

## 3) 打包出镜像

```bash
sudo bash scripts/extract-vendor-blobs.sh /dev/sdX   # 从一张能启动的 ArkOS/EmuELEC 卡 dd 出
                                                     # idbloader/uboot/trust 三块厂商 blob
                                                     # （版权原因不入库，哈希会记录并强校验）
make image                                           # 或只跑打包: bash scripts/image
```

`scripts/image` 挂载镜像后逐项核对，任何一项不过**不压缩直接退出**：

- `/lib/modules` 里**只有一棵内核树**；`.ko` 数量、`modules.dep` 在场、`build`/`source` 软链接已删；
- `extra` 里 aic8800_fdrv / aic_load_fw / rocknix-singleadc-joypad 的 **vermagic 与内核版本一致**
  （放错内核的模块不会报错，只会让 WiFi 和按键神秘消失）；
- **每个 `boot*.ini` 里 `load mmc 1:1 …` 点名的文件真的在 FAT 分区上** —— u-boot 2017.09 按字面
  文件名加载，写错一个名字就是黑屏，而这台机器没有串口去读那条错误；
- dtb 里 `amux-a/amux-en/rumble` 的极性标志；
- weston **存在但没有被 enable**；
- wifi-setup 的 service 与 timer **各自在 `.wants/` 里**：v20 那张卡连不上网就是因为这两个单元
  只在磁盘上、没被 enable，而 `r36-boot.txt` 的服务清单里根本没有它们，所以"日志里没提"
  什么都不证明 —— 这里断言的是"在场"，不是"没报错"；
- **ES 的启动器、二进制和两份 cfg 都在**，且 `es_input.cfg` 保留本板 SDL GUID
  `19009b4d4b4800000111000000010000` 与 `joystick1left`/`joystick1up` 两根轴，
  `es_systems.cfg` 至少有一个系统（缺文件时这个 fork 直接退出，零系统时主题根本不查）；
- 镜像里 **0 个 SSH 主机密钥**、首次开机生成单元到位、`machine-id` 为空、wpa 配置里没有
  `psk=`（凭据不进镜像）、dpkg manifest 在场、厂商 blob 哈希匹配。

确定性措施（v20 → v21 的差异）：固定 FAT volume id / ext4 UUID、rootfs 时间戳钳到
`SOURCE_DATE_EPOCH`（= HEAD 提交时间，可用 `R36_SOURCE_DATE_EPOCH` 覆盖）、
`cpio --reproducible` + 排序输入、`xz -T1`（`-T0` 的输出随宿主核心数变化）。

产物在 `target/`：`.img.xz` + `.sha256` + `.manifest.txt`（输入哈希、工具链版本、apt 快照、
dpkg 计数、产物哈希）。发布时把这三个文件抄进 `distributions/`。

## 关键版本改在哪里

| 要改什么 | 位置 |
| --- | --- |
| 内核版本 | `packages/kernel/linux/package.mk` 的 `PKG_VERSION` + `PKG_SHA256`（kernel.org sha256sums.asc） |
| 内核配置 | `projects/RK3326/linux/linux.aarch64.conf`（**`CONFIG_INPUT_POLLDEV=y` 不能掉**，见下） |
| apt 快照点 | `distributions/rk3326/options` 的 `APT_SNAPSHOT` |
| sysroot 的 -dev 集 | `packages/rk3326/rootfs-base/package.mk` 的 `R36_SYSROOT_DEBS` |
| 设备包集合 | `packages/virtual/image/package.mk` 的 `PKG_DEPENDS_TARGET` |
| 固定 UUID/volid | `distributions/rk3326/options`（改了要在发布记录里写一句） |

## 两条今天量出来的约束，别靠猜

1. **`CONFIG_INPUT_POLLDEV=y` 是摇杆驱动的前提**。拿一份没开这个符号的 `.config` 编内核，
   joypad 模块会在 modpost 阶段挂掉：
   `ERROR: modpost: "devm_input_allocate_polled_device" [rocknix-joypad.ko] undefined!`
   （实测 2026-10-04，本机 `/root/r36/linux-7.2.8/.config` 就是 `# CONFIG_INPUT_POLLDEV is not set`）。
   框架的 `projects/RK3326/linux/linux.aarch64.conf` 里这个符号是 `=y`，别拿旧树的 `.config` 顶替它。
2. **摇杆那五个补丁的前提变了**。`packages/kernel/rocknix-joypad` 现在 pin 的是 AveyondFly 的
   `7f3272ff…`（sha256 `3f8a48e4…`，实测与 GitHub archive 一致），这个 rev **已经自带** xifan
   震动补丁：`0001-add-xifan-device-vibrator` 与 `0002-add-vibration` 的 dry-run 都报
   "Reversed (or previously applied) patch detected"，只有
   `001-legacy-kernel-platform-remove-returns-int`、`003-export-joypad-input-g-and-vfs-ns`、
   `joypad-gpiod` 真会打上。而老的 ROCKNIX pin（`d02ed13…`）配这五个补丁是**复现不出**卡上驱动的
   （实测 1 + 4 + 10 个 hunk 失败，剩下的源码还在用 7.x 已删除的整数 GPIO 接口）。
   换句话说：现在能从源码编，靠的是换了 rev，不是补丁变好了。

## ES 装在镜像里的哪两个地方

`r36-es` 找二进制的第一个候选是 `/usr/local/bin/emulationstation`（`emulationstation` 包就装在那）。
配置文件 ES 只认两个文件名 —— `es_input.cfg` 和 `es_systems.cfg`，先在 `~/.emulationstation/`
找，再退到 `/etc/emulationstation/`。所以 `es-launcher` 包把仓库里的
`es-input-r36max2.cfg` **改名**装成 `es_input.cfg`（`packages/rk3326/es-launcher/package.mk`）：
按原名装进去等于没装，机器会停在"按任意键配置手柄"那一页，而这台机器没有键盘。
`es_systems.cfg` 必须一起装，否则这个 fork 打一条 `ERROR es_systems.cfg file does not exist!`
就退出，看起来像"ES 坏了"。

还没定过的一件事：卡上的 `~/.emulationstation/es_settings.cfg` 写着 `Language=zh_CN`
（还有 `LastSystem=favorites`、`ShowFlags/ShowTags=auto`），而镜像里目前不生成这个文件，
所以新卡第一次启动会是英文界面。要不要把中文界面带进镜像是产品决定，别让它悄悄漂移。

## 与 v20 流水线的关系

v20 的 16 步手工脚本（`build-all.sh`、`build-rootfs.sh`、`apply-v19.sh`、`pack-v20.sh`、
`v20-*.sh`……）已被上面这条框架取代，全部删除 —— git 历史完整，
`git log --diff-filter=D --name-only` 能找到删除它们的那次提交，再从那次提交的父提交取回。
`artifacts/prebuilt/`（手工取回的 `.ko`）与 `artifacts/es/`（从卡上 rsync 回来的 ES 二进制和主题）
也一并退出构建输入：模块和 ES 现在都由框架从锁定源码交叉编译。那批字节的证据留在 git 历史里
（`git show 617d040`：ES 二进制 117,246,560 B / sha `7bc65872…`，主题 1612 个文件与卡上逐字节一致）。

## 凭据与默认口令

默认镜像**不带 WiFi 凭据**，配网靠 `BOOT:\wifi.txt`（见 [WIFI-AND-SHARING.md](WIFI-AND-SHARING.md)）；
镜像也**不带 SSH 主机密钥**，首次开机由 `r36-hostkeys.service` 跑 `ssh-keygen -A`，`ssh.service`
有 drop-in 依赖它，否则 sshd 起不来。默认账号密码是 `ubuntu`/`ubuntu`，root 同样是 `ubuntu`
（`rootfs-apt` 里 `chpasswd` 设的），[FLASH.md](FLASH.md) 与卡上的 `r36-switches.txt` 都写了
刷机后第一件事是 `passwd`（另见 [SECURITY.md](SECURITY.md)）。
