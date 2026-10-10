# R36 Max 2 (RK3326) 上的 Ubuntu 26.04 —— 主线内核移植记录

一块 2023 年的 RK3326 掌机（稀范 R36 Max 2，1 GB RAM / 64 GB TF / 1024x768 DSI 屏 /
AIC8800DC USB WiFi），出厂跑 EmuELEC。这里记录的是**用主线内核 + 官方 Ubuntu 26.04 base
从零做一套通用 Linux 开发环境**的全过程。

> English (TL;DR): mainline Linux (latest 7.2.x since v21) + Ubuntu 26.04 on an RK3326
> handheld that ships EmuELEC. Board DTS, a ROCKNIX-style reproducible build framework
> (toolchain built from pinned sources, every input sha256-verified, deterministic image
> packing), rootfs config, a head-less EGL/GLES2 demo that proves the panfrost stack, a
> Weston session and a uinput joypad-to-mouse/keyboard bridge. Boot chain is unchanged
> (vendor u-boot reads `boot.ini` from the FAT partition), the eMMC is never touched, and
> pulling the card restores the stock system.

**不是**模拟器前端，也不是桌面系统 —— 目标是能 SSH、能编译、能跑图形 demo 的开发机。
所有结论都是真机量出来的，不是推测；没验的会写"没验"。

---

## 现在能用到什么程度

| 项目 | 状态 | 证据 / 详见 |
| --- | --- | --- |
| 引导（TF 卡双启动，eMMC 原样保留） | ✅ | u-boot 2017.09 → `boot.ini` → `booti` |
| 主线内核 7.2.9 + 板级 dtb（v21 起镜像里只有它） | ✅ | [`projects/RK3326/dt/`](projects/RK3326/dt/)，6.12.79 那条线见 [KERNELS.md](documentation/PER_DEVICE_DOCUMENTATION/r36max2/KERNELS.md) |
| 屏 / 背光 / 控制台 | ✅ | DSI 1024x768@60，fbcon 正常 |
| systemd + 网络 + SSH | ✅ | 40 秒内拿到 DHCP 地址 |
| WiFi（AIC8800DC，USB，chip_sub_id=2） | ✅ | 关联 -47 dBm，rx65/tx78 MBit/s |
| 按键 / 摇杆 / 电压采样 | ✅ | `retrogame_joypad`、`adc-keys`、`rk805 pwrkey` |
| 声音（rk817 codec + 外接功放） | ✅ | 耳机与喇叭都实测有声 |
| GPU（panfrost + Mesa + GBM + EGL） | ✅ | `Mali-G31 MC1 (Panfrost)`，GLES 3.1 → [GPU.md](documentation/PER_DEVICE_DOCUMENTATION/r36max2/GPU.md) |
| Wayland 图形会话（weston 14） | ⚠️ 起得来、能合成；VOP 会丢 vblank —— 有时永久卡死（只能重启），有时只是间歇 WARN 而画面仍可操作 | [WAYLAND.md](documentation/PER_DEVICE_DOCUMENTATION/r36max2/WAYLAND.md) |
| 摇杆→鼠标/键盘（uinput 桥） | ✅ 17 键 + 4 轴全部实机配对；但**跑 ES 时要停桥**（抢设备） | [JOYPAD-BRIDGE.md](documentation/PER_DEVICE_DOCUMENTATION/r36max2/JOYPAD-BRIDGE.md) |
| 虚拟键盘（`r36-osk`：uinput + wofi 网格） | ✅ 按键流已无人值守逐事件验证；点击那一步要屏幕能用 | [OSK.md](documentation/PER_DEVICE_DOCUMENTATION/r36max2/OSK.md) |
| EmulationStation（batocera 分支，桌面 GL） | ✅ 117 MB 二进制，**不需要 weston**：`r36-es --kmsdrm` 下目视确认出画面、摇杆切条目方向正确；22 秒窗口内内核 stall 计数 0→0 | [EMULATIONSTATION.md](documentation/PER_DEVICE_DOCUMENTATION/r36max2/EMULATIONSTATION.md) |
| 模拟器核（RetroArch + libretro，自编 9 个核 / 8 个可用系统） | ✅ nes·snes·gb·gbc·gba·psx 满速；dreamcast 55–59 fps（基本满速）；saturn 能启动出图但只有 14–15 fps。全部用游戏包里的**真游戏**在板子上两点取斜率量过，DC/SS 还截到了 SEGA 授权画面。第 9 个核 parallel-n64 已编好并装在镜像里，但**第一帧前空指针崩溃**，所以 n64 系统暂时从菜单里摘掉 | [EMULATORS.md](documentation/PER_DEVICE_DOCUMENTATION/r36max2/EMULATORS.md) |
| 开机自动进 ES + art-book 主题 + 默认音量 50% | ✅ 已进镜像（`r36-es.service`；主题 1614 个文件 + `es_settings.cfg` 选它；`audio.service` 设 128/255 并排在 `alsa-restore` 之后）。实测 50% = **-47.32 dB**，比想象的轻 | [EMULATORS.md](documentation/PER_DEVICE_DOCUMENTATION/r36max2/EMULATORS.md)、[EMULATIONSTATION.md](documentation/PER_DEVICE_DOCUMENTATION/r36max2/EMULATIONSTATION.md) |
| ES 里的 Wi-Fi 配网菜单（扫描 / 连接 / 忘记 / 屏幕键盘输密码 / 显示 IP地址） | ⚠️ 后端是这份仓库新写的 `/usr/bin/wifictl`，前端是 fork 里本来就有的 `GuiWifi.cpp`（它的菜单项原本被 `#if defined(BATOCERA)‖ROCKNIX` 挡在外面）。**"Wi-Fi 网络"这一行 2026-10-10 在屏幕上确认了**，十个子命令也逐个在卡上按 ES 的调用方式量过（连在用网络 → `key_mgmt=SAE`，连不存在的网络 → 失败且不掉的）；还没确认的是**在屏幕上走完一次真实连接**（含用屏幕键盘输密码），以及刚加的 **IP地址** 那一行（`patches/0105`，只验到"补丁干净应用 + `-fsyntax-only` 过 + 产物里就是那份二进制"，卡现在不在手上） | [WIFI-AND-SHARING.md](documentation/PER_DEVICE_DOCUMENTATION/r36max2/WIFI-AND-SHARING.md) |
| 根分区在线扩容 | ✅ | 2 GiB 镜像 → 58 GB，不重启 |
| PortMaster（社区移植游戏的安装器） | ⚠️ 运行时 pin 进镜像，port 能装能跑（Apotris 出图、有声、可输入），GUI `pugwash` 也在卡上跑通了（20 秒窗口 0 报错）—— 但这两样都是在**手工补齐**的那张卡上量的，等这一版镜像刷进卡里再确认一次 | [PORTMASTER.md](documentation/PER_DEVICE_DOCUMENTATION/r36max2/PORTMASTER.md) |
| 时间同步 | ✅ | timesyncd + 直接写 IP 的 NTP |
| 休眠 / 唤醒 | ❌ | 能进 `mem`，但**任何事件都叫不醒**，已 mask |
| 蓝牙 | ❌ | `hci0: command 0x204b tx timeout`（BT 固件未到位） |
| 视频硬解 | ❌ | 主线 rkvdec 不支持 px30/rk3326 |
| 桌面环境 | ❌ 故意不做 | 1 GB RAM 不值得 |

未做与已知的坑集中在 [KNOWN-ISSUES.md](documentation/PER_DEVICE_DOCUMENTATION/r36max2/KNOWN-ISSUES.md)。

## 从哪儿开始读

正文按主题拆进了 `documentation/PER_DEVICE_DOCUMENTATION/r36max2/`：

| 你要做的事 | 文档 |
| --- | --- |
| 认清这块板子（屏 / PMIC / WiFi 芯片 / USB 拓扑 / 无串口） | [HARDWARE.md](documentation/PER_DEVICE_DOCUMENTATION/r36max2/HARDWARE.md) |
| 在 WSL 里从内核打到镜像 | [BUILD.md](documentation/PER_DEVICE_DOCUMENTATION/r36max2/BUILD.md) |
| 刷卡、首启、BOOT 分区的开关文件 | [FLASH.md](documentation/PER_DEVICE_DOCUMENTATION/r36max2/FLASH.md) |
| 没有 UART 怎么拿到证据 | [DEBUGGING.md](documentation/PER_DEVICE_DOCUMENTATION/r36max2/DEBUGGING.md) |
| panfrost / EGL / GBM 的上层验证与三个坑 | [GPU.md](documentation/PER_DEVICE_DOCUMENTATION/r36max2/GPU.md) |
| weston 会话、截图为什么拿不到、vblank 卡死 | [WAYLAND.md](documentation/PER_DEVICE_DOCUMENTATION/r36max2/WAYLAND.md) |
| 摇杆当键鼠、屏上键盘 | [JOYPAD-BRIDGE.md](documentation/PER_DEVICE_DOCUMENTATION/r36max2/JOYPAD-BRIDGE.md)、[OSK.md](documentation/PER_DEVICE_DOCUMENTATION/r36max2/OSK.md) |
| 1 GB 内存上编出并跑起 EmulationStation | [EMULATIONSTATION.md](documentation/PER_DEVICE_DOCUMENTATION/r36max2/EMULATIONSTATION.md) |
| 模拟器核怎么编、怎么启动、每个系统实测多少帧、BIOS 放哪 | [EMULATORS.md](documentation/PER_DEVICE_DOCUMENTATION/r36max2/EMULATORS.md) |
| 7.2.8 怎么打上 ROCKNIX 的补丁层、6.12.79 那条线去哪了 | [KERNELS.md](documentation/PER_DEVICE_DOCUMENTATION/r36max2/KERNELS.md) |
| PortMaster 装 port 的整条路、这台板子要补的两处、GUI 缺的那三个库 | [PORTMASTER.md](documentation/PER_DEVICE_DOCUMENTATION/r36max2/PORTMASTER.md) |
| 换网络 / 交给别人用（不带凭据的镜像） | [WIFI-AND-SHARING.md](documentation/PER_DEVICE_DOCUMENTATION/r36max2/WIFI-AND-SHARING.md) |
| 还没解决的问题 | [KNOWN-ISSUES.md](documentation/PER_DEVICE_DOCUMENTATION/r36max2/KNOWN-ISSUES.md) |
| 许可、第三方来源、默认口令风险 | [LICENSING.md](documentation/PER_DEVICE_DOCUMENTATION/r36max2/LICENSING.md)、[SECURITY.md](documentation/PER_DEVICE_DOCUMENTATION/r36max2/SECURITY.md) |
| 每一版镜像的 sha256 | [distributions/README.md](distributions/README.md) |

这个目录里还留着三份更早的中文记录：`移植方案-R36Max2-Ubuntu.md`（最初的方案）、
`刷写与首启说明.md`（**v19 那版**的刷写说明，现行版本看上面的 FLASH.md）、
`上传GitHub步骤.md`。目录重排的来龙去脉见 [CHANGELOG.md](CHANGELOG.md)。

## 目录结构

顶层按 [ROCKNIX/distribution](https://github.com/ROCKNIX/distribution) 的角色划分组织，
仓库里只留**当前这一套（v21 构建框架）**在用的东西。命名对照：**v2…v20** = 历史镜像
版本号（`distributions/` 里每版一个 sha256，v21 是正在构建的这版）；**k72-** = 作者旧前缀，
意思是"内核 7.2 时期"，工具脚本现已全部改为语义命名；**r36-** = 装进 rootfs 跑在板子上的
设备包；**aic8800 / joypad** = WiFi / 摇杆两颗外设芯片的驱动：

```
projects/RK3326/   板子定义：dt/ 设备树（含 usbhost/gadget 变体、DRAM timing）、patches/ 内核补丁集
packages/           装进 rootfs、跑在板子上的 11 个包（键鼠桥、osk、weston 会话、ES 启动器、
                    bootlog、状态页、配网、扩根、固件切换、usb-gadget、gpu-demos）
scripts/            当前流水线：取内核、打补丁、编译、装 rootfs、打包镜像、lint（25 个）
tools/<子系统>/      被文档点名为证据来源的调试仪器（19 个），仍按
                    diagnostics（只读）/ runtime（改板子状态）/ verify（判定）分层
config/rootfs/      直接落进 rootfs 的配置
distributions/      每一版镜像的 sha256 与发布记录（*.img.xz 本体不入库）
documentation/      上面那些正文，外加最初的移植方案与 v19 那版的刷写记录
build/              本机 scratch，不入库：第三方源码、CMake 中间产物、wifi-cred.txt
```

历史上那些一次性探测脚本、编号草稿和被取代的版本流水线（约 360 个文件，原先摊在 `build/`
和后来的 `tools/`、`archive/` 里）已经不在工作树中。**没有丢**：它们都在 git 历史里，
用下面两条命令就能列出来并取回任意一个。判断"哪些算当前一套"的标准是文档 ——
`documentation/` 与 `README.md` 点名的脚本一律保留，其余按依赖闭包（`pack-v20.sh`
需要哪些前置就保留哪些）补齐。

```bash
git log --diff-filter=D --name-only --format=%h | less   # 哪次提交删了哪些文件
git show 6dd081a:tools/gpu/diagnostics/k72-vop-now.sh    # 取回某个被删的脚本
```

改完东西先跑 `make lint`（= `bash scripts/lint.sh`）：按 shebang 找出所有 shell 与 python
脚本做语法检查，并确认没有文件被放回 `build/`。GitHub Actions 跑的就是它。

保留下来的脚本里，绝对路径仍写作 `/mnt/e/ubuntu/...`（原作者的 WSL 构建机盘符），
换机器时换成你的仓库路径即可。

