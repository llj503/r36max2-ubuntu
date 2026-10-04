# R36 Max 2（RK3326）跑 Ubuntu 移植方案

目标：最新版 Ubuntu（26.04 LTS Resolute）作通用 Linux 开发/实验环境。
路线：**A = 复用厂商 5.10 BSP 内核 + 厂商 bootloader，只换 rootfs**（已选定）。
设备：稀范 R36 Max 2，RK3326(4×Cortex-A35)，976MB RAM，eMMC 3.7GB（EmuELEC 4.7），TF1 插 128GB ROMS 卡，**TF2 空槽**。

---

## 0. 已确认的关键事实（实测，非推测）

| 项 | 值 | 对方案的影响 |
|---|---|---|
| 内核 | Rockchip BSP **5.10.160**，`/flash/KERNEL`（arm64 Image，`ARMd` magic） | 直接复用，不编译 |
| 屏 | MIPI-DSI `sitronix,st7703` + `simple-panel-dsi`，**1.1KB 私有 init-sequence**，1024×768@62MHz，`fbcon=rotate:3` | 复用厂商 dtb 即可，无需移植 |
| 按键 | 厂商驱动 `"micro,gamepad"`：18 GPIO 键 + 4 路 SARADC 摇杆 + 震动 + RGB 灯 | 复用厂商 dtb 即可 |
| 电源/音频 | RK817（MFD+charger+battery+codec），全部 built-in | 复用即可 |
| GPU | Mali-G31 Bifrost，闭源 DDK g18p0 + `/usr/lib/libmali.so`；`CONFIG_DRM_PANFROST` 未开 | 开发机不需要 GPU，忽略 |
| WiFi | **AIC8800 挂在 USB 上**（不是 SDIO！），只有 2 个外部模块 `aic8800_fdrv.ko`/`aic_load_fw.ko` + `/usr/lib/firmware/aic8800DC/` | 拷进 rootfs 即可 |
| 启动链 | `idbloader.img`@32k·seek1 + `uboot.img`@64k·seek128 + `trust.img`@64k·seek192，厂商 U-Boot 2017.09，`boot.ini`→`sysboot`→extlinux | **完全不动 bootloader** |
| 内核 initramfs | `CONFIG_INITRAMFS_SOURCE=…/initramfs`（LibreELEC 的 /init，LZ4）**烧死在 Image 里** | ⚠️ 必须用外置 initrd 覆盖 /init |
| cgroup | **无 MEMCG、无 CGROUP_PIDS、无 BPF_SYSCALL、无 PSI**；设备侧是 systemd 252 + glibc 2.36 + hybrid cgroup | ⚠️ 最大风险，见 §4 |
| 磁盘 | eMMC 3.7GB 已满；TF1=ROMS(128GB)；**TF2 空** | Ubuntu 装独立 SD，eMMC 不动 |
| 设备侧工具 | 有 `parted mkfs.ext4 losetup cpio gzip tar xz blkid dtc curl wget depmod` + 能上外网 | **可在机器上自举构建，Windows 不需要 Linux 环境** |

已拉到本地的资产（校验过 md5）：`artifacts/KERNEL`、`rk3326-evb-lp3-v12-linux.dtb`、`idbloader.img`、`uboot.img`、`trust.img`、`boot.ini`、`extlinux.conf`、`config-5.10.160.gz`、`/storage/live.dts`（反编译设备树）。
已下载：`downloads/ubuntu-base-26.04.1-base-arm64.tar.gz`（35MB，sha256 已核对）。

---

## 1. 步骤总览（谁做什么）

| # | 步骤 | 在哪做 | 需要下载 | 大小 | 谁下载 |
|---|---|---|---|---|---|
| 1 | 准备 Ubuntu 卡（分区+格式化） | 设备 | 无 | — | 我 |
| 2 | 取 rootfs | 设备 curl 直连 cdimage | ubuntu-base-26.04.1-arm64.tar.gz | 35MB | 已完成/设备自取 |
| 3 | 配置 rootfs（passwd/ssh/网络/时区/模块/firmware） | 设备 chroot | apt 依赖包 | ~150–300MB | 设备自取 |
| 4 | 造覆盖用 initrd（busybox + /init + switch_root） | 设备 | busybox arm64 静态版（可选） | 2MB | 我 |
| 5 | 写 bootloader 三件套 + boot.ini/extlinux 到 Ubuntu 卡 | 设备 dd | 无（已有机件） | — | 我 |
| 6 | 插 TF1 试启动，看 systemd 能否起来 | 设备 | 无 | — | 你按电源 |
| 7 | 按结果分支：修 cmdlines / 退 22.04 / 重编内核 | — | 见 §4 | — | 讨论 |

**回退**：Ubuntu 卡拔掉 → 设备照旧从 eMMC 进 EmuELEC，ROMS 卡不动。零风险。

---

## 2. 详细步骤

### 步骤 1 — 分区（Ubuntu 专用卡，建议 ≥32GB）
把卡插 **TF1**（ROMS 卡挪到 TF2 或先取出）。在设备上：
- `parted /dev/mmcblk1 mklabel gpt`
- p1 FAT32 512MiB（`boot`：放 Image/dtb/initrd/extlinux/boot.ini）
- p2 ext4 剩余全部（`ubuntu`：rootfs）
- ⚠️ 这一步会清掉该卡数据，所以只用空卡。

### 步骤 2 — rootfs
设备直接 `curl -O https://cdimage.ubuntu.com/ubuntu-base/releases/26.04/release/ubuntu-base-26.04.1-base-arm64.tar.gz`，`tar -xvpPf` 解到 p2 挂载点（`-p` 保权限/软链，必须）。

### 步骤 3 — 配置（chroot 内，设备原生 aarch64，不需要 qemu）
- `mount -o bind /dev /proc /sys /sys/fs/cgroup` → `chroot`
- 写 `/etc/resolv.conf`（`192.168.31.1` 或 223.5.5.5）、apt 源（`ports.ubuntu.com` 或 `mirrors.aliyun.com/ubuntu-ports`）
- `passwd root`、建 `llj` 用户 + sudo
- `apt update && apt install -y openssh-system...`（openssh-server、systemd-networkd、iproute2、kmod、udev、apt-transport-https、ca-certificates、vim、git、build-essential、tmux、htop、zram-tools）
- `systemctl enable ssh systemd-networkd systemd-resolved`；networkd 配 DHCP
- 塞 WiFi：`aic_load_fw.ko`+`aic8800_fdrv.ko` → `/lib/modules/5.10.160/`，`aic8800DC/` → `/lib/firmware/`，跑 `depmod 5.10.160`，`/etc/modules` 加两个模块名
- 关 snap/桌面相关服务（1GB RAM）；加 2G swapfile 或 zram

### 步骤 4 — 覆盖 initrd（本方案的技术关键）
厂商 Image 内嵌 LibreELEC initramfs，会去找 `boot=UUID=… / SYSTEM squashfs`，不会挂我们的 rootfs。
外置 initrd 会在内嵌 initramfs **之后**解包进同一个 rootfs，**后解包的 `/init` 覆盖前者**，所以无需重编内核即可夺回启动流程。
- initrd 内容：`/init`（挂 devtmpfs/proc → `mount /dev/mmcblk1p2 /root -t ext4` → `exec switch_root /root /sbin/init`）+ busybox +（若用设备动态版 busybox）`ld-linux-aarch64.so.1`、`libc.so.6`、`libm.so.6`
- 打包：`find . | cpio -o -H newc | gzip > ubuntu-initrd.gz`（内核 `CONFIG_RD_GZIP=y` ✓）

### 步骤 5 — 启动文件
- `dd` 三件套到 Ubuntu 卡：`idbloader.img`（bs=32k seek=1）、`uboot.img`（bs=64k seek=128）、`trust.img`（bs=64k seek=192）——与设备 `/usr/share/bootloader/update.sh` 里的地址完全一致
- FAT 分区放：`KERNEL`（厂商原件）、`rk3326-evb-lp3-v12-linux.dtb`（厂商原件）、`ubuntu-initrd.gz`
- `boot.ini` + `extlinux/extlinux.conf`：
  ```
  LABEL Ubuntu
    LINUX /KERNEL
    FDT /rk3326-evb-lp3-v12-linux.dtb
    INITRD /ubuntu-initrd.gz
    APPEND root=/dev/mmcblk1p2 rootfstype=ext4 rw rootwait console=tty0 \
           fbcon=rotate:3 cgroup_enable=memory systemd.unified_cgroup_hierarchy=0 \
           smsc95xx.macaddr ignore_loglevel
  ```
  （cmdline 只作参考，实测调整；注意 `boot=`/`disk=`/`overlayroot=` 一律不要带）

### 步骤 6 — 首启动验证清单
1. 屏幕有 kernel log（无串口，屏是唯一 early 输出）
2. `systemd` 是否跑到 login（看屏）
3. WiFi：`ip a`、`wpa_passphrase` + `wpa_supplicant` 或 NetworkManager
4. 按键：`evtest`/`js0` 有事件；音量键；屏旋转
5. 电池/充电：`/sys/class/power_supply/*`
6. `free -m`、`apt` 是否可用

---

## 3. 你需要提供 / 决定的

1. **一张 ≥32GB 空 microSD**（Ubuntu 专用）。这是唯一的硬件前提。
2. 允许我把 ROMS 卡从 TF1 挪到 TF2（TF2 已确认是可用 SD 槽，`supports-sd`，与 TF1 独立供电/独立 cd-gpio）。
3. 确认 rootfs 用哪版 Ubuntu（默认按你说的"最新"= 26.04；风险见 §4）。

---

## 4. 最大风险：cgroup 缺失（决定要不要走到重编内核）

厂商内核 **没编 MEMCG / CGROUP_PIDS / BPF_SYSCALL / PSI**。设备自带的是 systemd 252 + hybrid cgroup，能跑；但 Ubuntu 24.04+（systemd 255/259）默认 unified cgroup2，缺 controller 时可能：
- 只是功能降级（`MemoryMax`/`TasksMax` 失效、无 PSI）→ 能用；
- 或者关键服务起不来（udevd 设备权限、logind）→ 不可用。

**这一点无法靠读代码断言，只能实测**（步骤 6 就能看出来，成本约半小时）。分支：

| 结果 | 处理 | 额外下载 |
|---|---|---|
| 6.1 能进 login | 收工，日常用 | — |
| 6.2 起不来但降级可接受 | 加 `systemd.unified_cgroup_hierarchy=0` 走 hybrid（Ubuntu 24.04 仍可） | — |
| 6.3 彻底不行（最省事的兜底） | 换 **Ubuntu 22.04** base（systemd 249，与设备 252 同代，肯定兼容） | 30MB，我来下 |
| 6.4 坚持 26.04 且必须完整 systemd | **重编厂商 5.10 内核**：`make menuconfig` 打开 MEMCG/CGROUP_PIDS/BPF_SYSCALL/PSI + 去掉 `INITRAMFS_SOURCE`，其余配置原样（用已存的 `config-5.10.160.gz`） | Rockchip 5.10 BSP 源码 ~150–200MB + aarch64 交叉工具链；需要 WSL2 或任意 Linux 主机 |

6.4 是唯一需要编译主机的路径；源码用厂商同款 Rockchip linux-5.10 BSP（含 `rk3326-evb-lp3-v12` 与 `micro_gamepad`/`simple-panel-dsi`/aic8800），配置照抄，**不涉及任何驱动移植**，所以比路线 B 便宜得多。

---

## 5. 附：本次我在设备上留下的改动

- `systemctl mask suspend.target sleep.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target`（远程调试防掉线）
  恢复：`systemctl unmask` 同名 target
- `iw dev wlan0 set power_save off` → 恢复 `on`
- 新增文件：`/storage/live.dts`（反编译设备树，方案依据，建议保留）
