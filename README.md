# R36 Max 2 (RK3326) 上的 Ubuntu 26.04 —— 主线内核移植记录

一块 2023 年的 RK3326 掌机（稀范 R36 Max 2，1 GB RAM / 64 GB TF / 1024x768 DSI 屏 /
AIC8800DC USB WiFi），出厂跑 EmuELEC。这里记录的是**用主线 6.12 内核 + 官方
Ubuntu 26.04 base 从零做一套通用 Linux 开发环境**的全过程：板级设备树、引导链、
rootfs 打包脚本、无串口时的调试通道、GPU 上层验证。

> English (TL;DR): mainline Linux 6.12.79 + Ubuntu 26.04 on an RK3326 handheld that
> ships EmuELEC. This repo holds the board DTS, the image build/pack scripts, the
> rootfs config, and a head-less EGL/GLES2 demo that proves the panfrost stack.
> Boot chain is unchanged (vendor u-boot reads `boot.ini` from the FAT partition),
> the eMMC is never touched, and pulling the card restores the stock system.

**不是**模拟器前端，也不是桌面系统 —— 目标是能 SSH、能编译、能跑图形 demo 的开发机。

---

## 现在能用到什么程度

| 项目 | 状态 | 证据 |
| --- | --- | --- |
| 引导（TF 卡双启动，eMMC 原样保留） | ✅ | u-boot 2017.09 → `boot.ini` → `booti` |
| 主线内核 6.12.79 + 板级 dtb | ✅ | `rk3326-xifan-r36max2.dts` |
| 屏 / 背光 / 控制台 | ✅ | DSI 1024x768@60，fbcon 正常 |
| systemd + 网络 + SSH | ✅ | 40 秒内拿到 DHCP 地址 |
| WiFi（AIC8800DC，USB，chip_sub_id=2） | ✅ | 关联 -47 dBm，rx65/tx78 MBit/s |
| 按键 / 摇杆 / 电压采样 | ✅ | `retrogame_joypad`、`adc-keys`、`rk805 pwrkey` |
| 声音（rk817 codec + 外接功放） | ✅ | 耳机与喇叭都实测有声 |
| GPU（panfrost + Mesa + GBM + EGL） | ✅ | `Mali-G31 MC1 (Panfrost)`，GLES 3.1，见下文 |
| 根分区在线扩容 | ✅ | 2 GiB 镜像 → 58 GB，不重启 |
| 时间同步 | ✅ | timesyncd + 直接写 IP 的 NTP |
| 休眠 / 唤醒 | ❌ | 能进 `mem`，但**任何事件都叫不醒**，已 mask |
| 蓝牙 | ❌ | `hci0: command 0x204b tx timeout`（BT 固件未到位） |
| 视频硬解 | ❌ | 主线 rkvdec 不支持 px30/rk3326 |
| 桌面环境 | ❌ 故意不做 | 1 GB RAM 不值得 |

## 硬件画像（省掉你插逻辑分析仪的时间）

- SoC RK3326 / PX30，4x A35，Mali-G31 MC1（Bifrost v7，panfrost 支持 GLES 3.1）。
- 屏：DSI，`panel-generic-dsi` + `panel_description`，实际是 ST7703 系克隆屏，原生 1024x768。
- PMIC rk805/rk817（`vdd_logic` 会被别的消费者顶在 975 mV —— 见 GPU 那节）。
- WiFi/BT：**AIC8800DC 是 USB 设备**（`a69c:88dc`，挂在 `ff300000` 的 dwc2 上），不是 SDIO。
  `chip_sub_id == 2` 属于 h_u02 版，需要 `fmacfw_patch_8800dc_h_u02.bin` 那一套固件。
- USB 拓扑：只有 dwc2 一个控制器且被 WiFi 占用 → **没有外置 host 口**，Type-C 插键盘没戏（试过）。
- 无 UART 焊盘、无调试串口 —— 所有远程观测靠 FAT 分区日志 + 屏幕状态页 + `/dev/fb0` 截图。
- 1 GB RAM；TF 卡分两个区：FAT `BOOT`（u-boot 读这里）+ ext4 根。

## 目录结构

```
board/            板级设备树（rk3326-xifan-r36max2.dts + usbhost/gadget 变体 + DRAM timing）
build/            全部构建与调试脚本（*.sh）、rootfs 里的脚本与 systemd 单元
  r36-bootlog*    开机状态报告 → BOOT:\r36-boot.txt
  r36-status-screen*  tty1 上的状态页（IP / 信号 / 失败单元 / 电量）
  r36-wpa@.service    不依赖 udev device 单元的 wpa_supplicant 模板
  r36-expand-root     在线扩根分区（只挪最后一个分区的结束扇区）
  99-r36-power.conf   logind 电源键策略
  r36-gles2-demo.c    无窗 GLES2/GBM demo（扫出 + 像素回读 + 测速）
  egl-probe.c         枚举 EGL config 并逐个试 window surface
  raw2png.py shot.sh  不拍照片就能看屏幕
out/              产物镜像与说明（*.img.xz 不入库）
```

## 从零构建

前置：WSL2 Ubuntu（或任意能交叉编译的 Debian 系），需要
`gcc-aarch64-linux-gnu device-tree-compiler rsync xz-utils squashfs-tools u-boot-tools sshpass`。

```bash
# 0) 准备目录
sudo mkdir -p /root/r36 && cd /root/r36
# 1) 内核：linux-6.12.79 + Rocknix 的三层补丁（mainline → devices/RK3326 → 6.12-LTS）
tar xf linux-6.12.79.tar.xz
cp board/rk3326-xifan-r36max2*.dts* linux-6.12.79/arch/arm64/boot/dts/rockchip/
#    并在该目录 Makefile 的 dtb-$(CONFIG_ARCH_ROCKCHIP) 里加一行
bash build/apply-mainline.sh
# 2) 内核 + dtbs + modules + 两个外部模块（joypad / aic8800）
bash build/build-all.sh
# 3) rootfs：ubuntu-base 解包 → apt 装包 → 写配置（WiFi 凭据从 build/wifi-cred.txt 读，别提交）
bash build/build-rootfs.sh
bash build/apply-v19.sh          # 把真机上验证过的改动回写进 rootfs
# 4) busybox initramfs（按 marker 文件找根分区）
bash build/build-initrd3.sh
# 5) 打包：MBR + idbloader/uboot/trust blob + FAT(BOOT) + ext4(2 GiB) → .img.xz
V=v19 bash build/pack-v10.sh
```

`pack-v10.sh` 需要三个厂商 blob（`idbloader.img` / `uboot.img` / `trust.img`），
从一张能启动的 ArkOS/EmuELEC 卡上 dd 出来即可（偏移 32 KiB / 8 MiB / 12 MiB）；
因为版权原因本仓库不分发它们，也不分发 EmuELEC 的 dtb。

## 刷写与首启

```bash
# 只刷 64 GB 那张卡；插回电脑后先确认设备号，别写错盘
xzcat out/r36max2-ubuntu-v19.img.xz | sudo dd of=/dev/sdX bs=8M status=progress oflag=sync
```

开机约 40 秒后 tty1 会出现状态页（IP、信号、失败单元、电量）。想关掉就在 BOOT 分区建空文件
`noscreen`。卡上的其它开关（建空文件即生效，删掉恢复）：

| 文件 | 作用 |
| --- | --- |
| `rescue` | 以 `rescue.target` 启动 |
| `usbhost` | 换 `rk3326-xifan-r36max2-usbhost.dtb`，打开第二组 USB 主机控制器 |
| `use-boot-fw` | 用 BOOT 分区 `fw/aic8800DC/` 里的固件替代系统内的，并重载 WiFi 驱动 |
| `r36-log` | 立刻再写一份状态报告到 `r36-boot.txt` |

## 没有串口怎么调试（这套方法比插 UART 更有用）

1. **FAT 分区当日志盘**：`r36-bootlog.timer` 每 2 分钟把 `ip`/`iw`/`rfkill`/`wpa_cli`/
   `systemctl --failed`/USB 拓扑/`/dev/input/by-path`/声卡/drm/devfreq/`dmesg`/
   `journalctl -b -p 4` 写进 `BOOT:\r36-boot.txt`。卡插回 Windows 就能读，一份报告能把
   整条因果链钉死。
2. **u-boot 启动失败会自己往 FAT 写 `error.log`** —— 引导层的免费证据（我就靠它发现
   `boot.ini` 里用 `${变量}` 当文件名会导致 `dtb load fail` 黑屏）。
3. **屏幕可以远程"看"**：`ssh root@dev "head -c N /dev/fb0"` → `raw2png.py`（纯 stdlib 的
   PNG writer）。这块屏 `virtual_size=1024,1536` 但可见只有 768 行、`bpp=32`、
   **没有 `line_length` 属性**（自己算 `W*4`）、字节序小端 BGRX。
4. `by-path`/`by-id` 目录空 = udevd 没跑；`ip a` 只有 lo = 驱动层问题；有 wlan0 无 IP =
   supplicant/DHCP 层。这个区分帮我找到了"rootfs 里没装 `udev` 包"这个真正的拦路虎
   （Ubuntu 24.04 起 `udevd` 从 `systemd` 拆出去了）。

## GPU 上层验证（panfrost + Mesa + GBM + EGL）

`build/r36-gles2-demo.c` 直接拿 DRM master、modeset DSI 连接器、建 GBM surface、
跑动画着色器并扫出，同时用 `glReadPixels` 把结果读回来做数值证明。实测：

| 场景 | 结果 |
| --- | --- |
| 扫出 1024x768（每帧一次 `drmModeSetCrtc`） | 29.8 fps（被显示管线串化成 60 Hz 的一半，不是 GPU 上限） |
| 离屏 FBO，轻着色器 | 59.0 fps / 46.4 Mpix/s |
| 离屏 FBO，48 迭代 Mandelbrot | 32.0 fps / 25.2 Mpix/s |
| devfreq | 负载 480–520 MHz，空载 200 MHz，governor `simple_ondemand` |

真机输出：

```
EGL config   : id 17  buf 30  depth 0  fourcc 0x30335258 (XR30)
GL renderer  : Mali-G31 MC1 (Panfrost)
GL version   : OpenGL ES 3.1 Mesa 26.0.8-1ubuntu0.3
RESULT       : 180 frames in 6.03s = 29.8 fps at 1024x768
readback     : px[0] = 250 242 216        # 和 shader 里的 vec3(0.98,0.95,0.85) 对上
```

镜像里把这两个程序都装好了（`/usr/local/bin/{r36-gles2-demo,egl-probe}`，源码与 Makefile 在
`/usr/local/share/r36-gpu/`），一条命令就能复现上面的结果：

```bash
r36-glcheck          # 6 秒动画扫到屏上，退出时把屏幕交回控制台
r36-glcheck fbo      # 离屏轻着色器
r36-glcheck heavy    # 离屏重着色器
r36-glcheck probe    # 枚举 EGL config 并逐个试 window surface
```

![GLES2 着色器扫出到掌机屏上（实拍）](001.jpg)

踩过的三个坑，全部值得记死：

1. **一个进程只能有一个 EGLDisplay**。先 `eglGetDisplay(gbm)`+`eglInitialize`+`eglChooseConfig`，
   之后再换成 `eglGetPlatformDisplayEXT` 的 display 并 `eglTerminate` 老的 —— config 属于
   已销毁的 display，`eglCreateContext` 必然 `0x3001 EGL_BAD_PARAMETER`。
2. **Mesa 的 GBM 平台只有 WINDOW 配置**：要 `EGL_PBUFFER_BIT` 直接返回 0 个 config，
   所以"pbuffer 离屏兜底"在这条路上不存在，离屏要自己建 FBO + renderbuffer
   （ES3 下 internalformat 用 `GL_RGBA8`，`GL_RGBA` 会 incomplete）。
3. **`gbm_surface` 的 fourcc 必须取自所选 config 的 `EGL_NATIVE_VISUAL_ID`**，硬写
   `GBM_FORMAT_XRGB8888` 会得到 `0x3009 EGL_BAD_MATCH`。另外 `eglChooseConfig` 的位深是
   **下界**语义，要 8/8/8+`EGL_BUFFER_SIZE 24` 仍会先命中 10-bit 的 XR30。

内核侧还有一个坑：panfrost `probe failed -22`。真因是一句
`vdd_logic: Restricting voltage, 975000-950000uV` —— 主线 `rk3326.dtsi` 的 GPU OPP 最低档要
950 mV，而 `vdd_logic` 已被别的消费者顶在 975 mV，regulator 核心遇到 min>max 直接 EINVAL，
死在 `panfrost_devfreq_init`。修法就是板级 dts 自带一张 OPP 表（见 `board/rk3326-xifan-r36max2.dts`
里的 `r36_gpu_opp`）。顺带：DTC 1.7.2 不接受在所有 `/ { }` 之外写带标签的裸节点。

## 换网络 / 交给别人用（这块板子没有键盘也没有串口）

镜像里可以完全不带任何凭据：`R36_BAKE_WIFI=0 bash build/build-rootfs.sh`。
使用者只需要在 Windows 上往 BOOT(FAT) 分区放一个两行的文本文件：

```
wifi.txt:
    SSID=我的WiFi名
    PSK=我的密码
    COUNTRY=CN        # 可选
```

`r36-wifi-setup.service` + `.timer`（开机 30 秒后、之后每分钟）发现文件内容变了，就用
`wpa_passphrase` 生成 `/etc/wpa_supplicant/wpa_supplicant-wlan0.conf`（**只存 PBKDF2 哈希**，
明文那行 `#psk=` 会被剥掉，权限 600），`iw reg set`、重启 `r36-wpa@wlan0`，等关联 + DHCP，
然后把结果写回 **`BOOT:\wifi-status.txt`**：

```
OK: connected to my-wifi, IPv4=192.168.31.57  (ssh root@192.168.31.57)
```

连不上的话这个文件会附上附近扫到的热点清单，所以在电脑上就能判断是密码错还是名字错，
不用拍屏幕。改完文件不用重刷也不用重启。

**注意 wifi.txt 是明文躺在 FAT 分区上的**（FAT 没有权限位）—— 公共场合或借给别人用之后，
删掉它；设备侧的配置文件里只有哈希。这个取舍和 Raspberry Pi OS 的 `network.txt` 一样，
是"没有任何输入通道"的板子唯一现实的做法。

## 已知问题与未做

- **睡眠能进不能出**：`echo mem` 进得去，电源键和 RTC 闹钟都叫不醒（只能长按强制断电）。
  `wakeup-source` 和 pwrkey 的 `power/wakeup` 都是好的，怀疑主线 `rk8xx` 没把 PMIC 中断注册成
  wakeirq，而厂商 BSP 依赖私有的 `rockchip,sleep-mode-config` + `rk817_slppin_*` 引脚复用。
  目前 `suspend/hibernate/sleep.target` 全 mask，电源键 `HandlePowerKey=ignore`
  （装了 udev 之后 logind 会开始抓 KEY_POWER，默认是 poweroff，实测短按就关机）。
  **测睡眠前一定先设 RTC 闹钟**，否则就是把设备关进小黑屋。
- 蓝牙 `hci0: command 0x204b tx timeout`：AIC 的 BT 固件没配好，必要时 blacklist `btusb`。
- 按键目前只有 input 事件，没有用户空间映射（掌机按键不能当键盘用：joystick 事件不会被
  内核 kbd handler 绑定，所以没法用按键登录）。
- 1 GB RAM：没上 zram/swap，编译大项目要省着点。

## 许可与第三方来源

- 我自己写的脚本、设备树、demo 与文档：GPL-2.0-or-later（与内核树同源，方便被抄回去）。
- `build/rocknix/`、`build/wifi/`、`build/aic-src/`、`build/joypad/*.tar.gz` 是第三方
  源码/补丁（Rocknix 项目、`radxa-pkg/aic8800`、JELOS joypad 驱动），已 `.gitignore` 排除，
  请按各自上游的许可证获取。
- Rockchip 的 `idbloader/uboot/trust` blob 与 EmuELEC/ArkOS 的镜像同样不分发。
- 用到的上游：torvalds/linux 6.12.y、Rocknix 的 RK3326 补丁层、radxa-pkg/aic8800 驱动、
  Mesa（panfrost）。

## 风险提示

所有实验都在 TF 卡上进行，eMMC 全程未写入 —— 拔掉卡就是原来的 EmuELEC。但改引导扇区、
刷错盘（我有两块卡，另一块是装着 ROM 的 128 GB）都会造成真实损失，动手前请先核对设备号。

**镜像的账号是 `ubuntu` / 密码 `ubuntu`（root 同密码）**，`build/dev-*.sh` 这些调试脚本里也
直接写着 `sshpass -p ubuntu`。这是调试期的权宜做法：刷机后第一件事请 `passwd` 改掉，并且
不要把改过的密码提交回来。`build/wifi-cred.txt`（WiFi SSID/口令）已在 `.gitignore` 里排除，
`build-rootfs.sh` 从它读取生成 `wpa_supplicant-wlan0.conf`（`chmod 600` 进镜像）。
