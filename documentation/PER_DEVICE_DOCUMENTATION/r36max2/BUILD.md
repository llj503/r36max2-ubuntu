# 从零构建

[← 返回 README](../../../README.md)

改完东西先跑 `make lint`（等价于 `bash scripts/lint.sh`）：按 shebang 找出所有 shell
与 python 脚本做语法检查，并确认没有文件被放回 `build/`。GitHub Actions 跑的就是它。

前置：WSL2 Ubuntu（或任意能交叉编译的 Debian 系），需要
`gcc-aarch64-linux-gnu device-tree-compiler rsync xz-utils squashfs-tools u-boot-tools sshpass`，
**外加 `qemu-user-static binfmt-support`** —— 后面每一步都要在 x86_64 上 chroot 进 arm64 的
rootfs 跑 apt/depmod/systemctl。这里有个真踩过的坑：binfmt 规则是写进
`/proc/sys/fs/binfmt_misc` 的运行时状态，**WSL 空闲超时把 VM 停掉就没了**，于是
`chroot ... /bin/sh` 变成 `Exec format error`。2026-10-04 那次就是这样：脚本一路把配置写完、
还打印了 `ROOTFS BUILD DONE`，而 rootfs 里一个包都没装上。现在 `scripts/build-rootfs.sh`、
`apply-v19.sh`、`apply-wayland.sh`、`v20-rootfs.sh` 动手前先调
`bash scripts/require-arm64.sh <rootfs>`（没有处理器就按 qemu 包里自带的规则注册，注册完
立刻验证 host 自己还能跑二进制 —— 手写规则如果把 e_machine 掩码弄错，会把 x86_64 的
`/usr/bin/ls` 也交给 qemu，整机立刻不可用，只能 `wsl --shutdown` 才救得回来）。

v21 是**单内核镜像**：只编 7.2.8，只装 7.2.8 的模块树。6.12.79 以前作为回退保险整套装在卡上，
现在那条路只留在 git 历史里（原因见 [KERNELS.md](KERNELS.md) 开头）。

## 1) 内核树

```bash
sudo mkdir -p /root/r36 && cd /root/r36
tar xf linux-7.2.8.tar.xz
bash scripts/k72-prepare.sh                                  # 搬 panel-generic-dsi.c + 挂 Kconfig + 装我们的 dts
K=/root/r36/linux-7.2.8 OUT=/root/r36/out72 bash scripts/build-all.sh   # 16 核 505 秒
```

`build-all.sh` 编内核 + dtbs + 模块树，再编 AIC8800DC WiFi 驱动。补丁层的处理方式见
[KERNELS.md](KERNELS.md)。

摇杆驱动**不在这条流水线上重编**：`build-all.sh` 的 [4/6] 会把 `projects/r36max2/patches/`
里那 5 个补丁往"解压干净的 pin 版本"上试一遍并如实报告 —— 2026-10-04 实测
`001-legacy-kernel-platform-remove-returns-int` 有 1 个 hunk、`0002-add-vibration` 有 4 个、
`joypad-gpiod` 有 10 个 hunk 打不上，剩下的源码里还留着 7.x 已经删掉的整数 GPIO 调用
（`gpio_set_value` / `of_get_named_gpio_flags` / `devm_gpio_request`），所以它编不过。
这不是构建脚本的 bug，是仓库里那份补丁集**复现不出卡上正在跑的驱动**；卡上那份是当初手工
改出来的。镜像因此只带 `artifacts/prebuilt/*.ko`。[4/6] 每次重跑这个测试，补丁哪天追上了就会
在日志里看见。

> 外部模块现在**不**从这棵构建树进镜像：`scripts/v20-rootfs.sh` 只认
> `artifacts/prebuilt/` 里在卡上实测过的那四份 `.ko`，并且逐个校 `MANIFEST.sha256` 与
> vermagic。原因见下面"自检"一节。

## 2) rootfs 与 initramfs

```bash
bash scripts/build-rootfs.sh     # ubuntu-base 解包 → apt 装包 → 写配置
                                 # WiFi 凭据从 build/wifi-cred.txt 读；发布用镜像请置 R36_BAKE_WIFI=0
bash scripts/apply-v19.sh        # 把真机上验证过的改动回写进 rootfs（幂等，可重复跑）
bash scripts/build-initrd3.sh    # busybox initramfs，按 marker 文件找根分区
```

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
```

`pack-v20.sh` 需要三个厂商 blob（`idbloader.img` / `uboot.img` / `trust.img`），从一张能启动的
ArkOS/EmuELEC 卡上 dd 出来即可（偏移 32 KiB / 8 MiB / 12 MiB）；因为版权原因本仓库不分发它们，
也不分发 EmuELEC 的 dtb。

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

## 更早的版本

v19 及以前的打包流程（`build-image*.sh`、`apply-v11..v17.sh`、v19 那版打包器）已经不在仓库里
—— 它们被上面这条 v20 流程取代了。需要时用 `git log --diff-filter=D --name-only` 找到删除它们
的那次提交，再从那次提交的父提交里取回文件。
