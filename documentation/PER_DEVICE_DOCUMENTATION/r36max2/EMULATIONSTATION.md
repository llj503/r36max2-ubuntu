# EmulationStation：在这台 1 GB 的板子上编出来并跑起来了

[← 返回 README](../../../README.md)

apt 里没有 ES（`emulationstation`、`emulationstation-de` 都不在 26.04），官网给的是 x86 .deb。
**ES-DE 的 aarch64 AppImage 起不了窗口**：它要桌面 GL 3.3+ 或 Vulkan，而本机 Mesa 26.0.8 只给
`GL_VERSION=3.1 Mesa` + `GLES 3.1`（Mali-G31/Panfrost），且 `/usr/share/vulkan/icd.d/` 是空的。
所以能走的只有 RetroPie/Batocera/ROCKNIX 这一支。最终采用
**`batocera-linux/batocera-emulationstation`**（`-DGL=ON`，桌面 GL）；
ROCKNIX 的 `emulationstation-next`（`-DGLES3=1`）也编到 73% 停在 `/root/esrn`，两棵树随时可续。

**1 GB 内存决定了几件事**（全部是实测，不是推测）：

- 用 `-j1`。`--parallel 2` 时两个 cc1plus 各 350–400 MB，SD 卡当交换盘被打爆
  （`/proc/pressure/io` avg10 71、45 秒墙上时间只用掉 12 秒 CPU）。
- `es-app/src/guis/GuiMenu.cpp`（batocera 5691 行 / ROCKNIX 7052 行）在 `-O3` 下 cc1plus 稳定
  705 MB，**21 分钟编不完**；把这一个 TU 降到 `-O1 -g0` 后 **4–5 分钟编完**、PSI 归零。
  判据是 PSI + "CPU 时间增量/墙上时间"，**不是** cmake 的 `[ N%]`。
- ⚠️ **降优化绝对不要重跑 cmake**：Unix Makefiles 生成器让每个 `.o` 都依赖 `flags.make`，
  一次 `cmake -S . -B build` 会把 141 个已编好的对象全判成过期（我踩过，进度从 73% 掉回 40%）。
  正确做法是把优化级别作为 **make 命令行变量**传进去：
  `cmake --build build --parallel 1 -- "CXX_FLAGS=<flags.make 里的原值> -O1 -g0"`
  —— 命令行赋值优先于 flags.make，GCC 取最后一个 `-O`/`-g`，而 `CXX_DEFINES`/`CXX_INCLUDES`
  仍由 flags.make 提供，所以不可能悄悄丢宏。真把时间戳弄脏了，`scripts/k72-esrn-recover.sh` 的
  救法是：先 `diff` 证明 flags.make 内容没变（变了就不敢复用旧对象），再 `touch` 全部 `.o`/`.a`。
- 产物**不在** `build/es-app/` 下：batocera 的 CMakeLists 把 `CMAKE_RUNTIME_OUTPUT_DIRECTORY`
  设成仓库根 → `/root/es/emulationstation`（117 MB）。照 ROCKNIX 树的路径去找会把"链接成功"
  当成"编译失败"（`tools/misc/diagnostics/k72-find-esbin.sh` 用日志里的 `Built target` + `find` 双重确认）。
- 依赖：`apt install gettext`。CMake 只在 `msgfmt + msgmerge + xgettext + Intl` 都在时才给
  `HAVE_INTL`；缺了它，26.04 的 libstdc++ 15 会让 `<iomanip>`→`<locale>` 拉进 `<libintl.h>`，
  和 ES 自带的 `ngettext` 回退实现撞成 `ambiguating new declaration`。**别删 ES 的回退**
  （这版 glibc 的 `<libintl.h>` 没有 `pgettext`，删了会变链接错误）。
- GitHub 的 archive tarball 不含子模块：pugixml 要按 `.gitmodules` 里 pin 的 sha 单独取
  （`scripts/k72-esrn-fix-pugixml.sh`）。

**冒烟测试故意分两阶段**（`tools/emulationstation/verify/es-smoke-device.sh`，跑在板子上，由 `/root/es-watch.sh` 在
链接完成那一刻自己触发；宿主侧 `scripts/k72-esrn-autorun.sh` + `tools/misc/runtime/k72-notify-wait.sh` 负责
"跑完了再通知"）：

- **batocera 的 ES 少了 `es_systems.cfg` 会直接退出**（`ERROR es_systems.cfg file does not
  exist!` → `Error while parsing systems configuration file!`），所以"什么都不装、看它活不活"
  这个 A 阶段设计对这支 fork 不成立；改成写一个合法但空的 `<systemList/>`，这样仍然零系统、
  不牵扯主题。实测 **alive after 25–30s = 1**，窗口/GL/SDL wayland 全通。
- B 阶段放一个假系统（`/root/roms/demo/mario.sh`，"启动"就是写个标记文件），从 SSH 注入两个
  **`ENTER`**（系统视图→游戏列表→启动）：标记文件写出 `ES launched the demo at 20:28:15`，
  ES 活着回到列表，内核 stall 计数 0→0。注意 ES 编译期默认键是方向键/Enter，所以不需要眼睛
  也能驱动它；`r36-osk` 的键名表里**没有 `RETURN`，只有 `ENTER`**（旧版打印 `injected 0/1`
  还返回 0，害我把自己的按键失误读成"ES 不响应"；现已加别名并且未知键名返回 2）。

**主题**用 `anthonycaccese/art-book-next-es`——ROCKNIX 在
`projects/ROCKNIX/packages/ui/themes/es-theme-art-book-next/package.mk` 里 pin 了 rev + sha256，
本机 `scripts/theme-stage-local.sh` 下载后校验到同一个 `7ee1e93f…`；它自己的 README 写明是
**Batocera ES 版**（适用 Batocera v40+/Knulli/ROCKNIX/RetroBat，基座就是
batocera-emulationstation），所以两支 fork 通用。`scripts/k72-es-theme-install.sh` 有两处与
上游做法不同，都是量出来的：安装用 **`cp -al` 硬链接**（同一文件系统，288 MB 一个字节都不重写），
以及**默认不裁剪** artwork 变体 —— 这份主题用
`<path>./_inc/systems/artwork-noir/_default.png</path>` 引用它们，而**不是**
`<include name="artwork-noir">`，照抄上游那句 `sed` 只删目录不删引用，实测留下 4 个缺失文件 +
4 处指进已删目录（`tools/theme/verify/theme-check-local.py` 把三种做法各测一遍）。装完还会在设备上再跑一次
引用自检。顺带一条：主题 XML 里写着裸 `&&`（`if="${a} == '1' && …"`），ES 的 tinyxml 能过、
Python 的 `ElementTree` 不过 —— **"我的解析器报错"不等于"文件坏了"**，checker 先转义再解析。

**手柄配置**：`es_input.cfg` 里必须写本机实测 GUID `19009b4d4b4800000111000000010000`
（Batocera 数据库里同名条目 `retrogame_joypad` 的 A/B 与 X/Y 和我们设备树的顺序是**反的**，
照抄会静默装反；js 按钮号 = `BTN_*` 码的升序排名）。读能力位图不要解析
`/sys/.../capabilities/key`（arm64 上是 64 位字且丢前导零），用 `EVIOCGBIT`
（`tools/capture/r36-capdump.py`）。菜单导航在这个 fork 里只认 `up/down/left/right` **或**
`joystick1left/joystick1up`（`es-core/src/InputConfig.cpp:229-238`：
`isMappedLike("left") = isMappedTo("left") || isMappedTo("joystick1left")`，反向由同一绑定取负
得到）；从 Batocera 模板抄来的 `leftanalog*` 在全代码库**零消费者**，等于白写。所以
`scripts/k72-es-sticknav.sh add` 补了两条轴绑定（`value=-1`，`id=0/1`）**并保留十字键**；
方向反了就 `... sticknav.sh flip`，回滚是 `undo`（原文件备份成 `es_input.cfg.pre-sticknav`）。

---

# 摇杆键鼠桥和 ES 抢同一个设备（重要）

`r36-keymapper` 用 `EVIOCGRAB` 独占摇杆。**桥在跑的时候 SDL 仍然"枚举"得到
`retrogame_joypad`（17 键 4 轴、GUID 正确），但读不到任何事件** —— ES 里手柄就像坏了，
只有桥转发出来的键盘/鼠标回声能用，而 A/B 被转成**鼠标点击**，ES 根本不绑鼠标，所以按 A 没反应。
`/usr/local/bin/r36-es` 的处理：**启动 ES 前 `systemctl stop r36-keymapper`，ES 退出（或
`r36-es --stop`）后自动 start 回来**（`watch_bridge` 后台守卫）。附带三条实测：

- `pgrep -x emulationstation` / `pkill -x emulationstation` **永远匹配不到**：`comm` 只有
  15 字符（`emulationstatio`），16 字符的 `-x` 恒为 0 —— 我用它写出一版"--stop 杀不掉 ES、
  还误报 ES 没在跑"的启动器。改用 `pgrep -c emulationstatio` 或按 argv[0] 匹配。
- `pgrep -f "$ES"` 会匹配到**自己的辅助进程**（旧版 watch_bridge 的 argv 里含
  `ESBIN='/root/es/emulationstation'`），于是"alive=2"是假的，守卫也永远等不到 ES 退出。
- 桥不处理 SIGTERM，每次 stop 都要等 systemd 超时再 SIGKILL，unit 从此显示 `failed`
  —— 那**是"停成功了"**，不是起不来；顺手把 `r36-keymapper.py` 加个信号处理是待办。
- 抓包侧同理：桥抢占设备时 `evtest` 打在摇杆节点上只有 capability 头、**0 个事件**，别当成
  "摇杆没信号"；要看原始 `BTN_*` 必须先停桥（`tools/input/diagnostics/k72-evcap.sh` 现在同时抓 4 个节点，
  uinput 那两个按设备名解析）。

---

# 不靠 weston 跑 ES：`r36-es --kmsdrm`（2026-10-04 实测）

`--kmsdrm` 让 ES 通过 SDL 的 KMS/DRM 后端**自己当 DRM master**，全屏直出，不需要合成器。
它做的事：weston 在跑就先停并等它真正放手（最多 40 秒，用 `fuser /dev/dri/card0` 确认，
还在就**拒绝启动**，否则 SDL 会阻塞在 `drmSetMaster` 上、看起来像内核挂了）；停掉键鼠桥；
`chvt 1` 拿回控制台；设 `SDL_VIDEODRIVER=kmsdrm`、`unset WAYLAND_DISPLAY XDG_RUNTIME_DIR`；
ES 退出后把桥恢复回去。

这条路的价值在于**绕开 weston 那一层**：省掉常驻 ~53 MB，也不走 weston 特有的
`does not support Atomic async page flip` → `drm_atomic_helper_commit_tail_rpm` 同步等 vblank
那条路。但注意它不是零风险：ES 自己照样翻页，同一个 VOP 的 stall 只是不再"由合成器触发"，
没被证明不存在。

**实测数据**（22 秒窗口，`timeout 22 r36-es --kmsdrm`，板子 7.2.8、可用内存 726 MB）：

| 指标 | 结果 |
| --- | --- |
| ES 进程 | 第 8 秒 `pgrep -c emulationstatio` = **1**，跑满窗口 |
| 退出原因 | `rc=124`（timeout 到点杀的，不是自己崩） |
| 内核 stall 计数 | 启动前 `0`，结束后 **`0`** —— `dmesg \| grep -c 'timed out'` 无增量 |
| 结束后的服务 | `weston=inactive`、`r36-keymapper=inactive`（都没被拉起来） |
| 控制台 | `vtcon1/bind=1`，fbcon 回来了 |
| ES 日志里唯一的错误 | `HttpReq::onError (3): Could not connect to server` —— ES 自己的联网请求；这块板子的 `resolv.conf` 还烧着旧网关 `192.168.31.1`，出网本来就不通，与渲染无关 |

没有 `Failed to initialize renderer` / SDL 初始化失败那类行，说明它过了渲染后端初始化进了主循环。
**屏上真的画出了 ES，摇杆能移动光标、能切条目，方向正确**（2026-10-04 作者目视确认）。这一条
程序侧本来就拿不到证据 —— 截图被合成器权限模型挡住，kmsdrm 下更是没有合成器可截。

意义比"ES 能跑"更大一点：这台 1 GB 的板子**完全可以不开 weston** 就用摇杆操作 ES，
于是那条 weston 会把 VOP 弄死的风险线被整条绕开了。

顺手修掉一个真实缺陷（`packages/r36-emulationstation/r36-es`）：`bridge_on()` 原来是无条件
`systemctl start r36-keymapper`，而该单元带 `BindsTo=weston.service` —— 于是 `--kmsdrm` 一退出
就会把 weston 一起拽起来，恰好是这条路径刻意要躲的东西。现在只在"ES 启动前桥本来就在跑"
（`BRIDGE_WAS=active`）时才恢复，`watch_bridge()` 那个后台守卫同样加了这层判断。
