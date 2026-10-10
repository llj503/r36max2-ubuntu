# PortMaster（社区移植游戏的安装与运行）

[← 返回 README](../../../README.md)

PortMaster 是"给掌机装社区移植"的那个工具：它自己不是模拟器，它按设备档案下载、校验、
接线别人已经编好的游戏 port。这一层是 2026-10-10 加进来的。

## 镜像里带什么，不带什么

| | |
| --- | --- |
| 带 | **pin 住的官方运行时**：`/usr/config/PortMaster/release/PortMaster.zip`，来自 PortsMaster/PortMaster-GUI release `2026.10.03-1041`，24,131,471 字节，sha256 `6e4fa938c39efdb9237aa9973b3ce3f318242ada171f26cd72511b09e393fdf2`（同时和 release 公布的 md5 `742c4f335bd44ec03b7872510b098912` 对过） |
| 不带 | 解压后的 control folder。PortMaster 更新时会重写自己那个目录，构建期放一份只会变成"又一个会过期的东西"。首次启动才解到 `/roms/ports/PortMaster`（ROCKNIX 也是这个做法） |
| 不带 | **port 本体**（决定：只装运行时，port 在设备上联网自装）。这样镜像才可复现 —— 一个 port 是一次下载，不是构建产物 |
| 不支持 | **armhf 的 port**。镜像是 arm64-only，没有 32 位 multilib，`/lib/ld-linux-armhf.so.3` 不存在。这类 port 装了也起不来，只能挑 arm64 的 |

`PKG_DEPENDS_TARGET` 里 `portmaster` 挂在 `image` 上，构建时 zip 落 `sources/portmaster/`
并被 sha256 校验后才进 `${INSTALL}`。

## 怎么启动

* ES：`Ports` 系统里的 `Start PortMaster.sh`（`es_systems.cfg` 把 `/roms/ports` 下
  `.sh` 直接列成条目，command 是 `/usr/local/bin/r36-port %ROM%`）→ `r36-portmaster`。
* 控制台/SSH：直接 `r36-portmaster`。

PortMaster 找自己 control folder 的顺序（`PortMaster.sh` 开头几行，实测）：

```
/opt/system/Tools/PortMaster  →  /opt/tools/PortMaster  →  $XDG_DATA_HOME/PortMaster  →  /roms/ports/PortMaster
```

我们落在最后一个兜底项上，所以前三个**必须不存在**；`r36-portmaster` 如果发现
`$XDG_DATA_HOME/PortMaster` 存在会明确报错叫你删掉，否则它会用那个目录而不是卡上这个。

## 这台板子上游不认，两处必须补（都是实测出来的，不是猜的）

**1. `get_controls()` 里没有这台机的摇杆分支。** 它逐个 probe
`/dev/input/by-path/` 上已知掌机的节点名，而这台机的节点是
`platform-rocknix-singleadc-joypad-event-joystick`（模块 `rocknix_singleadc_joypad`），
带 `rocknix-` 前缀；上游最接近的分支找的是不带前缀的那个。实测 pin 的这份 release 里
`singleadc-joypad-event-joystick` 只出现 1 次，`platform-rocknix-...` 一次都没有。

没有分支匹配 → 从 ES 启动 port 时 `get_controls` 是**不带参数**调的，于是 `DEVICE` 留空 →
`grep "${SDLDBUSERFILE}" -e ""` 空模式匹配所有行 → 整个 1798 行的 `gamecontrollerdb.txt`
（约 472 KB）被塞进**一个**环境变量 → 超过 `MAX_ARG_STRLEN`（128 KB）→ 之后每一次
`execve` 都 `E2BIG`：`sudo`、`pidof`、游戏二进制全部报 "Argument list too long"，
一个 port 都起不动。

`packages/portmaster/overlay/fix_control.py` 在 anchor（`  else\n    DEVICE="${1}"`）前插一条
`elif`，把 `DEVICE` 设成本机 GUID、`param_device="r36max2"`。它只认**恰好一个** anchor：
数量不是 1 就打印实际数量并 exit 1，不去猜上游改成了什么。（pin 的这份 release 实测
`control.txt` 7158 字节、anchor 恰好 1 个、没有 `platform-rocknix-` 分支。）

顺带一件实测到的事：这台机器 `device_info.txt` 给出的是 `CFW_NAME=Ubuntu`（卡上实测），而
release 里**没有** `mod_Ubuntu.txt`（`ls` 只有 Batocera / ArkOS / dArkOS / EmuELEC / JELOS /
Miyoo / REGLinux / ROCKNIX / TrimUI / UnofficialOS / knulli / muOS / spruce 和一个空名
`mod_.txt`），所以 `PortMaster.sh:20` 的
`[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source ...` 是空操作 —— 少了一层别的 CFW
会带进来的目录/路径改写，这反而更干净。

**2. SDL 映射行。** 上游数据库里这条 GUID 一行都没有（实测 0 行），所以
`overlay/gamecontrollerdb-r36max2.txt` 带着它：

```
19009b4d4b4800000111000000010000,retrogame_joypad,a:b0,b:b1,x:b3,y:b2,back:b8,start:b9,guide:b10,...
```

`a=south b=east x=west y=north` 是 SDL 的语义，本机按键索引是 SOUTH0 EAST1 NORTH2 WEST3，
所以是 `a:b0,b:b1,x:b3,y:b2` —— 和 `packages/rk3326/es-launcher/es-input-r36max2.cfg` 里
记的一致。

这两处**每次启动都重新施加**（`r36-portmaster`），PortMaster 自更新替换 `control.txt` 也
不会被悄悄还原；`scripts/image` 的自检缺任何一个都直接判打包失败。

## GUI 起不来的那一步：三个 SDL2 扩展库

`pugwash` 是 PortMaster 的 SDL2 图形界面。它 import 的 python 侧（PySDL2 的 `sdl2`、
`harbourmaster`、`loguru`、`requests`、`png`、`pugscene`/`pugtheme`/`pySDL2gui`/`utility`）
全在 release 自带的 `pylibs.zip`（11,286,520 字节，实测在这个 zip 里；pugwash 首启自己解压，
还会从 `NotoSans.tar.xz` 里取出字体）—— **这些不用 apt 装**。

要从 apt 来的只有 `.so`：`libsdl2-ttf-2.0-0`、`libsdl2-image-2.0-0`、`libsdl2-gfx-1.0-0`
（`libSDL2_mixer` 已经随 `libsdl2-mixer-dev` 在镜像里）。两个坑：

* PySDL2 缺库时**不报 ImportError**，它只是不建那个子模块，于是失败长这样
  （2026-10-10 在卡上实测）：`AttributeError: module 'sdl2' has no attribute 'sdlimage'`。
* 手工 `cp` 那几个 `.so` 上去不够。`libsdl2-image-2.0-0` 自己还 Depends
  `libjpeg8 / libpng16-16t64 / libtiff6 / libwebp7 / libwebpdemux2`，
  `libsdl2-ttf-2.0-0` Depends `libfreetype6 / libharfbuzz0b`（快照 `apt-cache depends` 实测）——
  只有走 apt 才会把闭包带全。

## 顺手修的一个噪声

Ubuntu base tarball 的 `/etc/hosts` 是**空的**，于是每个程序都刷
`sudo: unable to resolve host r36max2`，把真正有用的行埋掉 —— PortMaster 每个 port 的输出
一开始看着就是这样。`rootfs-apt` 现在在 `/etc/hostname` 之后写 `/etc/hosts`
（`127.0.1.1 r36max2`）。

## 实测状态

| 项 | 状态 |
| --- | --- |
| 在这张卡上装一个 port 并跑起来（Apotris） | ✅ 2026-10-10 跑了两遍（第二遍是在四个库改成 dpkg 装的之后）：`r36-port` 起，窗口内 **0 个 renderer 错误、0 段错误、0 个 E2BIG**，两次都是 `timeout` 停掉的（rc=124）。用的正是上面两处修复 |
| `pugwash` 图形界面完整跑起来 | ✅ 2026-10-10，**0 个 DLLWarning、0 个 AttributeError、0 个 Traceback**，harbourmaster 认出的设备是 `{'name': 'ubuntu', 'version': '26.04', 'kernel_version': '7.2.9', 'device': 'xifan r36max2', 'resolution': (1024, 768), 'gpu_driver': 'panfrost', 'primary_arch': 'aarch64', 'ram': 1024, 'glibc': '2.43'}`。这张卡上那四个库是用构建机下好的同一批 deb `dpkg -i` 补的（`apt-get install` 在卡上会撞上 `util-linux` 的精确 PreDepends，见 KNOWN-ISSUES），装完 `.so` 与新镜像里的**逐字节相同** |
| 用 `r36-portmaster` 走完整流程（种子解包 → 每次启动重施两处修复 → 起 GUI） | ⚠️ 每一步单独验过，`r36-portmaster` 这个入口串起来也跑过，但**是在手工补的卡上**；`2ef50cd4` 那一版镜像还没刷进卡 |
| 第一次起 GUI 时的一条抓取失败 | `harbourmaster.util:fetch - Failed to download 'https://api.github.com/repos/PortsMaster/PortMaster-Info/git/trees/main?recursive=1'` —— 当场复查：同一个 URL 返回 **http=200、total=0.96 s、`x-ratelimit-remaining: 50`**（未登录限额 60/小时）。所以是**一次瞬时限流/抖动**，不是这台机的问题；port 索引要靠这条线，装不上 port 时先量它而不是先改镜像 |
| 无害噪声 | `Failed to restart oga_events.service: Unit not found` —— `PortMaster.sh:186` 无条件 `$ESUDO systemctl restart oga_events &`，本机没有这个单元。不改上游脚本 |
| 无害噪声 | `/roms/ports/PortMaster/control.txt: line 72: [: sudo: binary operator expected` —— 上游第 72 行写的是 `[ -z $ESUDO ]`（没引号），而它自己在第 50 行把 `ESUDO` 设成 `sudo --preserve-env=...`（带空格），于是 `[` 收到 3 个参数。走错的分支只是给 RetroArch 系端口准备 `raloc/raconf` 的，本机用不上 |
| 无害噪声 | `Failed to open PWM: No such file or directory` —— Apotris 自己找的 PWM 节点（蜂鸣/震动）本机没有 |

## 踩过的一个坑：不能在 ES 还占着显示的时候从命令行起 port

这张卡上实测过两次，差别只在 ES 在不在：

| 情况 | 结果 |
| --- | --- |
| `r36-es` **active**，SSH 里直接 `r36-port Apotris.sh` | 刷屏 `Failed to create texture: Parameter 'renderer' is invalid`，然后 `Segmentation fault`。SDL 拿不到 DRM master，`SDL_CreateRenderer` 返回 NULL，后面每次建纹理都继承这个 NULL |
| `systemctl stop r36-es` 之后再跑 | 干净，0 错误 |

**从 ES 里选 port 不会有这个问题**：这个 fork 在游戏启动路径上就先把渲染器放掉了 ——
`es-app/src/FileData.cpp:718` 读 `HideWindow`，`window->deinit(hideWindow)`，而
`es-core/src/Settings.cpp:362-366` 的默认值是 `#if defined(_WIN32) || defined(X86) || defined(X86_64)` 才
false，**交叉到 arm64 就是 true**；`Window::deinit(true)` 里会 `Renderer::deinit()`。
所以只有"ES 还在前台、你从另一个终端起 port"这种手工测试才会撞上。量帧/量端口记得先
`systemctl stop r36-es`，测完 `systemctl start r36-es`。

`XDG_RUNTIME_DIR` 不用管：用 `env -i HOME=/root PATH=... SDL_VIDEODRIVER=kmsdrm
SDL_AUDIODRIVER=alsa` 起 pugwash，0 条 XDG 报错 —— `r36-es.service` 的环境里也只有
`HOME=/root`。之前那条 "XDG_RUNTIME_DIR is invalid" 是 `sudo` 打的，不是 GUI。

## 设备上想绕过 GUI 直接装

`harbourmaster` 是随 release 一起的 CLI：`update` / `list` / `install` / `uninstall` /
`ports` / `device_info` / `runtime_*`。install 的参数形式是 **`[source/]<port>.zip`**
（不带 `.zip` 会说找不到，这个坑踩过）。

