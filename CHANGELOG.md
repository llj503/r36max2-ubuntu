# v21 —— 可复现构建框架(对齐 ROCKNIX/distribution)

v20 的构建是"16 步手工脚本 + 作者机器上的隐形输入":14 个外部输入只有 2 个做过哈希
校验;安装脚本从不读仓库里的 `packages/`,读的是 `/mnt/e/ubuntu/build` 下的临时拷贝;
apt 对活动镜像实时装;打包把墙钟时间、随机 UUID、按核心数变化的 xz 压缩全部烧进镜像。
v21 把它重写成 ROCKNIX 式框架:**先自建交叉工具链,再按 package.mk 依赖图构建,最后
打包镜像**,任何人拿同一份仓库应能复现出同一个镜像。

## 构建模型(替换 v20 的 16 步手工流水线)

| v20 | v21 |
| --- | --- |
| 手工解包内核 tarball(无 URL 无哈希) | `packages/kernel/linux/package.mk` pin 7.2.9 + SHA256,`scripts/get` 强制校验 |
| `/root/r36` + `/mnt/e/ubuntu` 硬编码路径 | 一切路径来自 `config/path`(`make build PKG=...`) |
| 用作者宿主机的 aarch64 gcc | binutils 2.44 + gcc 15.1.0 自建进 `build.*/toolchain`,sysroot 由 ubuntu-base + pinned -dev deb 填充 |
| `build-rootfs.sh` 实时 apt(aliyun 镜像) | `r36-rootfs-apt` 对 **snapshot.ubuntu.com 固定时间点**安装,dpkg 清单随镜像发布 |
| `packages/` 是摆设,脚本读 `/mnt/e` 拷贝 | 13 个设备包全部从 `packages/<名>/` 安装,仓库是唯一来源 |
| `pack-v20.sh` 烧入 `date -Is`/随机 UUID/`xz -T0` | 固定 volid/UUID、`SOURCE_DATE_EPOCH`(= HEAD 提交时间)、`cpio --reproducible`、`xz -T1` |
| WiFi 凭据默认烤入(`R36_BAKE_WIFI=1`) | **永不烤入**,BOOT:\wifi.txt 是唯一配网通道;resolv.conf 只留公共 DNS(v20 硬编码作者家路由) |
| ES 在 1 GB 板子上编(-O1 降级、两阶段冒烟) | ES + 主题按 rev+sha256 锁定交叉编译进镜像 |

入口:`make checkdeps → make source → make build image → make image`。
唯一需要 sudo 的是 chroot apt 一步。详见 [BUILD.md](documentation/PER_DEVICE_DOCUMENTATION/r36max2/BUILD.md)。

## 输入清单(全部锁定,写在各自 package.mk)

linux-7.2.9(kernel.org)、busybox 1.38.0、rocknix-joypad@7f3272ff(AveyondFly,
joypad-gpiod 补丁仍由本仓维护)、aic8800@5.0+git20260123.5f7be68d-9(radxa-pkg,
7.2.8 兼容补丁实测干净应用)、aic8800DC 固件@4.0+git20250410.b99ca8b6-5(上游 5.0 起
删了 8800DC 的 .bin,固件单独 pin)、ubuntu-base 26.04.1(cdimage SHA256)、
emulationstation-next@cada856d(ROCKNIX,v20 真机校验过的同一 tarball)、
art-book-next-es@9a50ef36(同 v20 主题 pin)。厂商 u-boot 三 blob 不可分发,
`scripts/extract-vendor-blobs.sh` 从现成 ArkOS 卡 dd 出来,哈希记录后强校验。

## 模拟器层（v21 出镜像之后加进来的）

Ubuntu 仓库里有 RetroArch 但**一个 libretro 核都没有**，所以 8 个核全部由
`packages/libretro/*/package.mk` 从 pin 死的 commit 交叉编译（策略：能编就编，编不了才拷 ——
目前没有一个核是拷来的）。启动链是 `ES → r36-play → retroarch --appendconfig=/etc/r36/retroarch.cfg`，
成绩与踩的坑（flycast 的 `platform=arm64`/`AS`/atomics、satune 与 mgba 的 LTO、三家 BIOS 的
不同路径、以及"标称 FPS 不能当成绩"这件事）都在
[EMULATORS.md](documentation/PER_DEVICE_DOCUMENTATION/r36max2/EMULATORS.md)。
`scripts/image` 现在逐条核对镜像里的 `es_systems.cfg`：每个 `<core>` 要有对应的 `.so`，
每个 `<path>` 要存在且非空。

## 其它变化

- **单内核**:v20 的双内核保险(6.12.79 同卡回退)按决定移除,镜像只带 7.2 系最新,
  FAT 分区文件名回到朴素的 `Image`/`rk3326-xifan-r36max2.dtb`。
- **panel-generic-dsi 入库**:主线没有 `rocknix,generic-dsi`,现 vendored(GPL 头保留)
  + 7.x API 适配补丁(`devm_drm_panel_alloc`、`linux/hex.h`);dmc/dfi 惰性节点
  (上游同样无驱动消费)以 board 补丁加进 px30.dtsi。
- **可读性**:`k72-` 前缀(作者"内核 7.2 时期"的缩写)全部改为语义名
  (evcap/flip-churn/wedge-probe/...),README 增加命名对照。
- **删除** 24 个 v20 流水线脚本与全部 k72-*/主题真机脚本(git 历史完整);
  `lint.sh` 新增三条规则:脚本禁含旧机路径、每个 package.mk 必须 pin 输入、
  `build/`/`sources/`/`target/`/`build.*` 不入库。
- v20 打包器的压缩前校验门全部保留并扩展(dpkg manifest 在场、blob 哈希匹配)。
