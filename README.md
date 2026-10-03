# R36 Max 2 (RK3326) 上的 Ubuntu 26.04 —— 主线内核移植记录

一块 2023 年的 RK3326 掌机（稀范 R36 Max 2，1 GB RAM / 64 GB TF / 1024x768 DSI 屏 /
AIC8800DC USB WiFi），出厂跑 EmuELEC。这里记录的是**用主线内核（v20 起默认 7.2.8，
6.12.79 同卡保留）+ 官方 Ubuntu 26.04 base 从零做一套通用 Linux 开发环境**的全过程：
板级设备树、引导链、rootfs 打包脚本、无串口时的调试通道、GPU 上层验证、Wayland 与
摇杆输入。

> English (TL;DR): mainline Linux (7.2.8 by default since image v20, 6.12.79 kept on the
> same card as a one-rename fallback) + Ubuntu 26.04 on an RK3326 handheld that ships
> EmuELEC. This repo holds the board DTS, the image build/pack scripts, the rootfs
> config, a head-less EGL/GLES2 demo that proves the panfrost stack, a Weston session
> and a uinput joypad-to-mouse/keyboard bridge.
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
| Wayland 图形会话（weston 14） | ⚠️ 起得来、能合成，但会让 VOP 翻页永久卡死（只能重启） | `r36-wayland start`，见下文 |
| 摇杆→鼠标/键盘（uinput 桥） | ✅ 17 键 + 4 轴全部实机配对 | `build/r36-keymapper.py`，见下文 |
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

### 出 v20（双内核 + Wayland + 摇杆键鼠桥）的实际顺序

v20 不是"再跑一遍老脚本"，它把 7.2.8、gpiod 摇杆、WiFi 兼容补丁和图形栈一起收进来，
所以顺序和检查点都记在 `build/v20-*.sh` 里，按编号执行：

```bash
bash build/v20-stage72.sh      # 7.2.8 的 Image / 三份 dtb 落到 out/boot，核对 dtb 里的 gpio 极性标志
bash build/v20-aic72b.sh       # 干净的 AIC 源码副本 + 7.2.8 兼容补丁 -> 对 7.2.8 重编 -> 与卡上正在用的 .ko 比 sha
bash build/v20-rootfs.sh       # 两个内核的模块树进 rootfs，逐个 modinfo 断言 vermagic，chroot 里 depmod + modprobe -n
bash build/apply-v19.sh        # 把真机验证过的改动回写（幂等，可重复跑）
bash build/v20-clean-wpa.sh    # 删掉被 mask 单元的残留 wants 软链（masked+enabled 会在开机报错）
python3 build/v20-hostkeys.py  # 扫凭据 + 把镜像里的 SSH 主机密钥换成首次开机现生成
bash build/apply-wayland.sh    # weston/foot/wofi/grim/wf-recorder/kbd + weston.ini/service + 键鼠桥（不 enable）
bash build/v20-tidy.sh         # apt cache / lists / 大日志清掉，量一下要塞进 2 GiB 分区的内容
V=v20 bash build/pack-v20.sh   # 打包，并在压缩前自检（见下）
```

`pack-v20.sh` 的自检不是装饰：它挂载镜像后逐项核对**两个内核各自的 .ko 数量、
extra 模块的 vermagic 与内核版本一致**（放错内核的模块不会报错，只会让 WiFi 和按键
神秘消失）、dtb 里 `amux-a/amux-en/rumble` 的极性标志、weston **存在但没有被 enable**、
镜像里 **0 个 SSH 主机密钥** 且首次开机生成单元到位、`machine-id` 为空、没有任何
wpa 凭据文件、`build`/`source` 软链接已删除；任何一项不过就**不压缩**、直接退出。

两处与"给别人用"相关的安全改动，v20 起才成立：**镜像不带 WiFi 凭据**（靠
`BOOT:\wifi.txt` 配网，见下一节），**镜像不带 SSH 主机密钥**（`r36-hostkeys.service`
在首次开机 `ssh-keygen -A`，`ssh.service` 加 drop-in 依赖它，否则 sshd 起不来）。
默认账号密码仍是 `ubuntu`/`ubuntu`，README 与 `r36-switches.txt` 都写了刷机后第一件事是 `passwd`。

## 刷写与首启

```bash
# 只刷 64 GB 那张卡；插回电脑后先确认设备号，别写错盘
xzcat out/r36max2-ubuntu-v20.img.xz | sudo dd of=/dev/sdX bs=8M status=progress oflag=sync
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

## Wayland（weston）：让屏幕显示图形界面

选型是 **weston 14.0.2**（Ubuntu 26.04 里的参考实现），`--backend=drm` 直接从
GBM/panfrost 起，不需要 X 或别的合成器垫在前面。内存实测：weston 常驻 53 MB（peak
58.8 MB，单元上挂 `MemoryHigh=320M` 只限速不 OOM），同时开着 `foot` +
`weston-simple-egl` + `weston-flower` + `wofi` 之后仍有 ~580 MB available。

- 安装：`apt install weston wayland-protocols libwayland-dev grim wf-recorder foot wofi
  cmake pkg-config`。Ubuntu **没有 `weston-examples`** 这个包，示例客户端
  （`weston-simple-egl`、`weston-flower`、`weston-screenshooter`）都在 `weston` 包里；
  而 apt 只要遇到一个不存在的包名就**整条命令什么都不装**（`E: Unable to locate package`
  后面紧跟着一句看起来像成功的 `apt exit=0`），所以 `build/k72-wayland-install.sh`
  先用 `apt-cache policy` 过滤再安装。
- 落地的文件（都在仓库里，装完设备与将来出镜像用同一批）：
  `build/weston.ini` → `/etc/xdg/weston/weston.ini`；
  `build/weston.service` → systemd 单元，**默认 disabled**，因为合成器一拿 DRM master
  就会把 tty1 的状态页顶掉；
  `build/r36-wayland` → `/usr/local/bin/r36-wayland`（`start|stop|status|run <app>|egl|
  term|smoke [秒]|shot|apps|env`）；`build/zz-r36-wayland.sh` → `/etc/profile.d/`，只在
  socket 存在时导出 `XDG_RUNTIME_DIR=/run/wayland WAYLAND_DISPLAY=wayland-0`。
- 用法：`r36-wayland start` → `r36-wayland run foot`（或 `r36-wayland smoke 30` 摆两个
  GL 客户端）。从 SSH 起的程序直接显示在屏幕上，这就是这台没键盘的机器的日常姿势。
- 三个实测坑：
  1. **weston 14 已经没有 `--tty=` 选项**。`fatal: unhandled option: --tty=/dev/tty2`
     发生在 backend 已经初始化、DSI-1 已经 modeset、EGL config 都选好之后，所以日志看着
     像成功，进程却立刻退出。VT 由 session/libseat 决定；以 root 跑 systemd 服务直接就能
     拿到 DRM master（配 `Conflicts=getty@tty1.service` + `ExecStopPost=chvt 1` 让控制台回来）。
  2. **截图被合成器的权限模型挡住**：`weston-screenshooter` 回
     `Output capture error: unauthorized`，`grim`/`wf-recorder` 需要
     `wlr-screencopy-unstable-v1`（weston 不实现）。libweston 里
     `weston_compositor_add_screenshot_authority` 只把捕获权交给"由用户按键触发的那次请求"，
     ini 没有开关；`build/r36-shot.py`、`build/r36-shot2.py` 试过直接请求、先挂请求再注入
     6 种组合键、全盘找新文件，都没能拿到 PNG。**所以图形验收目前仍然靠眼睛/拍照。**
  3. **意外收获：`/dev/uinput` 虚拟键盘这条路是通的**（uinput 内核内建，不需要模块）。
     `r36-shot.py` 造出键盘后 weston 立刻记录
     `event4 - r36-shot-virtual-keyboard: is tagged by udev as: Keyboard` 并把它关联到
     DSI-1 —— 这正是以后做"摇杆→键盘/鼠标"桥的现成地基。结构体大小有讲究：
     `struct uinput_user_dev` 的 abs 数组是 `__s32`，`ff_effects_max` 后面**没有填充**，
     总共 80+8+4+4×64×4 = **1116 字节**，写 1120 直接 `EINVAL`。
     注入按键时还顺手撞开了 weston 的 flight recorder（`Ctrl+Alt+P` 起 / 再按停，
     30 秒写出 `/capture.wcap` 10 MB、524 帧，magic `PACWXR24`），那是合成器侧调试的现成数据源。
- **⚠️ 7.2.8 上 weston 会把显示管线永久卡死（真机踩到，只有重启能清）**：weston 启动日志里就写着
  `DRM: does not support Atomic async page flip`（RK3326 的 VOP 没有原子异步翻页），于是内核走
  `drm_atomic_helper_commit_tail_rpm` 这条**在提交里同步等 vblank** 的退路。跑了 23 分钟、
  客户端退出拆面的时候出现第一条 `WARNING drivers/gpu/drm/drm_atomic_helper.c:1921 ... wait_for_vblanks`，
  之后 `rockchip-drm: vblank wait timed out on crtc 0` / `flip_done timed out` /
  `[CRTC:39:crtc-0] commit wait timed out` 每 10–40 秒循环，面板冻在最后一帧（看起来是"白屏带四角暗块"）。
  **停 weston、`chvt 1`、写 `fb0/blank=0` 都救不回来**，vsync 中断已经不再来了。下次尝试顺序：
  `[core] pageflip-timeout=500` → 一次只开一个客户端并盯 `journalctl -k` → 切 `boot-612.ini` 做 A/B
  （6.12 上我们自己的 GBM 直出翻页能跑到 29.8 fps，所以能区分是 weston 的翻页方式还是 7.2 的
  rockchip-drm 回归）。两个恢复陷阱：`weston.service` 的 `ExecStopPost=chvt 1` 在装 `kbd` 之前
  是**静默失败**的（这镜像原本没有 chvt/fgconsole，所以"active vt"一直打印空）；刚开机
  `fb0 blank` 读数是 4（DPMS 关闭），往 tty1 写一次东西才亮——**没键盘的机器上"屏黑"和"死机"
  长得一模一样，别急着长按电源**。
- 刻意设置的：`locking=false` + `idle-time=0` —— 这台机器睡眠进得去出不来，一个锁掉的
  屏等于把设备关小黑屋；`gbm-format=xrgb8888` 与之前 GBM/EGL 验证选到的格式一致；
  光标缺 `dnd-*` 只影响拖拽图标，无功能性问题。

## 摇杆当键鼠用（uinput 桥）

`build/r36-keymapper.py`（纯标准库）读摇杆的 evdev 节点，用 `/dev/uinput` 造一个键盘 +
一个鼠标重新发出去。内核内建 uinput，不需要模块，**也不需要合成器在跑**——验证映射的方法
就是读那两个新 event 节点，完全不碰 DRM，所以它能安全地单独使用、单独关掉。

| 摇杆 | 发出 | 实测 |
| --- | --- | --- |
| 左摇杆 | `REL_X/REL_Y`，死区 ±220、满推 24 px/tick、1.7 次曲线 | 单 tick 最大 ±24 ✓ |
| 右摇杆 | `REL_WHEEL(_HI_RES)` / `REL_HWHEEL(_HI_RES)`，每 0.16s 一格 | ±1 格 / ±120 hi-res ✓ |
| A / B / L3 | `BTN_LEFT` / `BTN_RIGHT` / `BTN_MIDDLE` | down/up 成对 ✓ |
| X / Y | `KEY_BACKSPACE` / `KEY_SPACE` | ✓ |
| 方向键 | `KEY_UP/DOWN/LEFT/RIGHT` | ✓ |
| SELECT / START / MODE | `KEY_ESC` / `KEY_ENTER` / `KEY_LEFTMETA` | ✓ |
| L / R / L2 / R2 | `KEY_LEFTCTRL` / `KEY_LEFTALT` / `KEY_LEFTSHIFT` / `KEY_TAB` | ✓ |
| R3 | `KEY_END` | ✓ |

17 个键 + 4 根轴全部实机验过，没有"只 down 没 up"的卡键。

- 用法：临时跑 `systemd-run --unit=r36-km-test /usr/bin/python3 /usr/local/bin/r36-keymapper.py -v`，
  `systemctl stop r36-km-test` 就还原；长期用则是 `r36-keymapper.service`
  （`BindsTo=weston.service` + `WantedBy=weston.service`，起合成器自动带上、停合成器自动撤）。
  默认 `EVIOCGRAB` 抓走摇杆节点，避免同一按键既当按键又当手柄；`--no-grab` 可并存，
  `--selftest` 只打印映射表不碰设备，`--dry-run` 只读不发。
- **两个必须记的坑**：① `REL_MAX` 只有 **0x0f** —— `REL_WHEEL=8`、`REL_HWHEEL=6`，
  按 27/28 传 `UI_SET_RELBIT` 直接 `EINVAL`，鼠标设备根本建不起来（键盘却是好的，
  所以现象像"只有一半能用"）；② `struct uinput_user_dev` 必须**正好 1116 字节**
  （abs 数组是 `__s32`，`ff_effects_max` 后面没有填充），多 4 字节就 EINVAL，
  且写记录要在 `UI_DEV_CREATE` 之前。
- 设计取舍：滚轮值是**格数**不是像素（第一版复用指针速度曲线，一次翻 23 格＝整页飞）；
  17 个键覆盖不了字母输入，**打字仍然要靠 SSH 或屏上键盘**。这座桥的目标是"指针 + 最常用键"，
  不是虚拟全键盘。

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

## 内核版本：6.12.79（镜像默认）与 7.2.8（已移植）

主线 7.2.8（2026-09-25 发布）在这块板子上**已经跑通并真机验证**（显示、音频、GPU、
WiFi、摇杆 17 键 + 4 轴 + 震动全部实测）。**v20 起默认内核就是 7.2.8**，6.12.79 仍然
完整装在同一张卡上：BOOT 分区里 `boot.ini` 是 `boot-72.ini` 的副本，想退回就把
`boot-612.ini` 覆盖成 `boot.ini`，不用重刷。唯一还需要小心的是 weston —— 见上面
"Wayland"一节里那条 ⚠️，它只在开合成器时才会发作，所以图形栈装了但默认不启动。

| | 6.12.79 | 7.2.8 |
| --- | --- | --- |
| 构建 | `K=/root/r36/linux-6.12.79 bash build/build-all.sh` | `K=/root/r36/linux-7.2.8 bash build/build-all.sh`（16 核 505 秒） |
| 补丁层 | 全部干净应用 | 11/24 干净；13 个 panfrost 冲突**直接丢掉**（上游已实现 `SET_LABEL_BO`、`SYSTEM_TIMESTAMP`） |
| 显示 / 音频 / GPU / WiFi | ✅ | ✅（WiFi 需下面的兼容补丁） |
| 摇杆 joypad | ✅ | ✅（需下面的 gpiod 改写 + 配套 dtb 极性） |

7.2.8 需要四件事，都在这里：

1. **`build/k72-prepare.sh`** —— 打补丁 + 把 Rocknix 的 `panel-generic-dsi.c` 搬进
   `drivers/gpu/drm/panel/`（主线没有 `rocknix,generic-dsi`），并把它挂进 Kconfig。
   两个坑：Kconfig 条目必须在最后一个 `endmenu` **之前**，且依赖名是 `DRM_MIPI_DSI`
   而不是 `MIPI_DSI` —— 写错时 `scripts/config --enable` **静默无效**，症状是面板驱动
   根本不编译，开机黑屏。
2. **面板驱动适配新 DRM 接口**：`hex2bin` 移到 `<linux/hex.h>`；`drm_panel_init()`
   不再是驱动可用接口，改用 `devm_drm_panel_alloc(dev, struct generic_panel, panel,
   funcs, DRM_MODE_CONNECTOR_DSI)`，它返回 **ERR_PTR**（不是 NULL），所以判空要写
   `IS_ERR/PTR_ERR`。
3. **`build/aic8800-7.2.8-compat.patch`**（221 行，4 个文件）—— 给 radxa-pkg 那份
   AIC8800 驱动打上游 API 搬家补丁：`cfg80211_ops` 十几个回调首参
   `net_device *` → `wireless_dev *`（用转发 wrapper，不动函数体）、
   `cfg80211_new_sta/del_sta` 收 wdev、`get_tx_power` 多 `radio_idx`/`link_id`、
   `remain_on_channel` 多 `rx_addr`、`in_irq()` → `in_hardirq()`、
   **`strncpy()` 已从内核移除** → `strscpy()`、`ieee80211_mgmt` 的 action 内层 union
   变匿名且 `action_code` 上提。打完 `make -C drivers/aic8800 KDIR=<tree> modules`
   零 error，产物与真机验证过的那份**逐字节相同**。
4. **`build/joypad-gpiod.patch`**（473 行，24 个 hunk，两个文件）—— 把
   `rocknix-singleadc-joypad.c` / `rocknix-joypad.c` 从整数 GPIO API 改写成 gpiod
   消费者 API，同一份源码在 6.12 与 7.x 都能编。改写本身不难，难的是它牵出两个
   **完全静默**的坑，值得单独写清楚：
   - **`gpiod_set_value()` 会按设备树极性取反，`gpio_set_value()` 不会。** 逐行改名
     等于把每一个 `GPIO_ACTIVE_LOW` 脚的电平反过来。这块板子上：ADC 复用器的
     `amux-en`（低电平才接通）被反过来 → 复用器全程断开，四根轴和电压梯按键全读
     悬空脚；地址位 `amux-a` 被反过来 → 每次选通道都选错。现在的约定写死在
     `board/rk3326-xifan-r36max2.dts` 的注释里：地址位声明 `ACTIVE_HIGH`（逻辑==物理），
     `amux-en` 保留 `ACTIVE_LOW` 而驱动改成**逻辑断言**（接通写 1），`rumble-gpio`
     实测高电平转 → `ACTIVE_HIGH`。
   - **裸的 `gpios` 属性必须传 `con_id = NULL`。** gpiolib 用
     `gpio_suffixes = {"gpios","gpio"}` 拼候选名：con_id 非空时只找
     `"<con_id>-gpios"` / `"<con_id>-gpio"`，con_id 为 NULL 才找裸 `gpios`。传字符串
     `"gpios"` 就变成去找 `gpios-gpios`，永远 -ENOENT；而这段代码对 -ENOENT 是
     **故意容忍**的（desc 置 NULL 继续跑），于是模块加载正常、17 个键码都注册进
     input、`/sys/kernel/debug/gpio` 里一个消费者都没有、dmesg 一条错都不打。
     顺带解释了一个假象：厂商 DT 把震动写成单数 `rumble-gpio`，正好命中第二条后缀，
     所以 `devm_gpiod_get_optional(dev,"rumble",...)` 看起来"能用"。
   - **改 DT 极性必须重启才生效，重载模块没用；只改驱动则 `rmmod` + `modprobe` 即可。**
   - 判定手法：`cat /sys/kernel/debug/gpio` 看 label 有没有被认领，比读代码猜错误码快得多。
     抓事件用 `build/k72-evcap.sh` + `build/k72-evread.sh`（注意本机 evtest 1.36
     **没有 `--raw`**，带上它只会写一份 usage 进文件；正常模式事件行是
     `type 1 (EV_KEY), code 304 (BTN_SOUTH), value 1`，`value` 前有逗号）。
   - 真机结果：17 个 GPIO 键 down/up 全部成对，四根轴 `ABS_X/Y/RX/RY` 满行程 ±1800，
     `adc-keys` 的音量加减正常，震动用 `build/r36-rumble.c` 走标准 FF 通路验证
     （焊盘 hi=转、随后回 lo=停；`struct ff_effect` 在这个 ABI 上是 **48 字节**，
     自己拼缓冲区会 EFAULT，所以在设备上用 `<linux/input.h>` 编译最稳）。

**换内核的安全网**（这套做法让升级变成低风险操作）：BOOT 分区里的文件全部带版本后缀
（`Image` / `Image-7.2.8`、`rk3326-xifan-r36max2.dtb` / `…-7.2.8.dtb`、
`boot.ini` / `boot-72.ini` / `boot-612.ini`），u-boot 只认 `boot.ini` 这个文件名，
所以**切换 = 改文件名**，不重刷、不碰 eMMC，失败了长按断电换回来即可。

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
- **摇杆还差的两件小事**：轴方向只验证了"满行程能打到 ±1800"，没逐方向核对
  `invert-absx/absry` 这几个厂商调过的标志，也没验证单 ADC 电压梯的**组合键**
  （比如同时按两个键产生的中间电压档）；6.12.79 那条线目前跑的还是镜像里自带的整数
  GPIO 版模块，gpiod 版虽然同样能编（同一份源码），但没在 6.12 上重装验证过——
  注意它和新 dtb 的极性是配套的，别只换一半。
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
