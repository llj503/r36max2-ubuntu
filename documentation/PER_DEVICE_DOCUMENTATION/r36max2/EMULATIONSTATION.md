# EmulationStation：在这台 1 GB 的板子上编出来并跑起来了

[← 返回 README](../../../README.md)

> **v21 状态**：ES 改为**交叉编译进镜像**（锁定 batocera 分支 commit + art-book-next 主题
> sha256，见 `packages/` 的 emulationstation/主题包）。本文其余部分是这个二进制最初
> **怎么在板子上被编出来**的完整记录——内存约束、坑、判定手法全部仍然成立；
> 文中提到的 `scripts/k72-*` 脚本已随 v20 流水线删除，需要时用
> `git log --diff-filter=D --name-only` 找到删除提交后 `git show <提交>^:<路径>` 取回。

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
  仍由 flags.make 提供，所以不可能悄悄丢宏。真把时间戳弄脏了，当时的救法（git 历史里的
  `scripts/k72-esrn-recover.sh`）是：先 `diff` 证明 flags.make 内容没变（变了就不敢复用旧对象），
  再 `touch` 全部 `.o`/`.a`。
- 产物**不在** `build/es-app/` 下：batocera 的 CMakeLists 把 `CMAKE_RUNTIME_OUTPUT_DIRECTORY`
  设成仓库根 → `/root/es/emulationstation`（117 MB）。照 ROCKNIX 树的路径去找会把"链接成功"
  当成"编译失败"（`tools/misc/diagnostics/find-esbin.sh` 用日志里的 `Built target` + `find` 双重确认）。
- 依赖：`apt install gettext`。CMake 只在 `msgfmt + msgmerge + xgettext + Intl` 都在时才给
  `HAVE_INTL`；缺了它，26.04 的 libstdc++ 15 会让 `<iomanip>`→`<locale>` 拉进 `<libintl.h>`，
  和 ES 自带的 `ngettext` 回退实现撞成 `ambiguating new declaration`。**别删 ES 的回退**
  （这版 glibc 的 `<libintl.h>` 没有 `pgettext`，删了会变链接错误）。
- GitHub 的 archive tarball 不含子模块：pugixml 要按 `.gitmodules` 里 pin 的 sha 单独取
  （当时用 `scripts/k72-esrn-fix-pugixml.sh`，commit pin 保留在该脚本的历史里）。

**冒烟测试故意分两阶段**（`tools/emulationstation/verify/es-smoke-device.sh`，跑在板子上，由 `/root/es-watch.sh` 在
链接完成那一刻自己触发；宿主侧当时的 `scripts/k72-esrn-autorun.sh`（已删，见顶部注记）+ `tools/misc/runtime/notify-wait.sh` 负责
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

**主题**用 `anthonycaccese/art-book-next-es`——上游 pin 的 rev + sha256 与本机下载校验一致
（`7ee1e93f…`，现为 `theme-stage-local.sh` 历史与主题包的 pin）；它自己的 README 写明是
**Batocera ES 版**（适用 Batocera v40+/Knulli/ROCKNIX/RetroBat，基座就是
batocera-emulationstation），所以两支 fork 通用。当时的安装脚本（`scripts/k72-es-theme-install.sh`，已删）有两处与
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
得到）；从 Batocera 模板抄来的 `leftanalog*` 在全代码库**零消费者**，等于白写。所以轴绑定要
**补两条**（`joystick1left/joystick1up`，`value=-1`，`id=0/1`）**并保留十字键**；
方向反了就把 `value` 取反，回滚先备份原文件（当时的 `scripts/k72-es-sticknav.sh add/flip/undo`
已删，绑定的最终形态固化在 `packages/rk3326/es-launcher/es-input-*.cfg` 里）。

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
  "摇杆没信号"；要看原始 `BTN_*` 必须先停桥（`tools/input/diagnostics/evcap.sh` 现在同时抓 4 个节点，
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

---

# 界面语言：为什么"选简体中文没反应"（2026-10-09 实测）

用户在设置菜单里选"简体中文"，界面毫无变化。查下来是**三个独立的洞叠在一起**，每一个都
足够让翻译失效，而且都不报错：

1. **卡上一个 catalog 都没有。** `find / -xdev -name emulationstation2.mo` = 0。这个 build 带
   `-DHAVE_INTL`（`CMakeLists.txt:558-560`，`es-core.dir/flags.make` 的 `CXX_DEFINES` 里能看到），
   所以 `_(x)` 就是 glibc gettext（`es-core/src/LocaleES.h`）；Linux 分支里**没有**自带的 .po
   解析器 —— 那套 `mItems` / `checkLocalisationLoaded` 在 `LocaleES.cpp:88` 之后的 `#else`
   （WIN32）分支里。上游的安装规则是 `share/locale/<lang>/LC_MESSAGES`
   （`locale/CMakeLists.txt:33`），而本仓库的 `makeinstall_target` 从不跑 `make install`。
2. **设置项根本没被用上。** `main.cpp:345-348` 只调用 `EsLocale::init("", "/usr/share/locale")`
   —— locale 传空串；全树 grep `EsLocale::init` 的调用者只有这一处，没有任何代码把保存下来的
   `Language` 交给 `setenv`/`setlocale`。菜单里的"简体中文"确实存在
   （`GuiMenu.cpp:1545`），保存也确实生效（`SystemConf::set("system.language")` 在无
   batocera.conf 时映射成 es_settings.cfg 的 `Language`，`SystemConf.cpp:18-19`），但
   **界面语言只由环境变量决定**。
3. **glibc 在 C 系 locale 下无视 LANGUAGE。** 这个 rootfs `locale -a` 只有 `C / C.utf8 / POSIX`，
   也没有 `/usr/share/i18n` 数据（`localedef -i zh_CN -f UTF-8` 报
   `character map file 'UTF-8' not found`）。用板上同一个 glibc gettext（python3 的
   `locale.gettext` 走的就是 C 库）配合真实的 zh_CN catalog 实测：

| 环境 | `gettext("SETTINGS")` |
| --- | --- |
| `LANG=C.UTF-8 LANGUAGE=zh_CN` | `SETTINGS`（英文，被忽略） |
| `LC_ALL=C LANGUAGE=zh_CN` | `SETTINGS`（英文，被忽略） |
| `LANG=C.UTF-8 LC_MESSAGES=zh_CN.UTF-8` | **`设置`** |

也就是说：**必须有生成好的 locale**，只把 `LANGUAGE` 塞进环境是没用的。

## 修法（三处，全部实测）

* `packages/ui/emulationstation/package.mk`：把 i18n target 编出来的 35 个
  `emulationstation2.mo`（在**源码树** `locale/lang/<lang>/LC_MESSAGES/`，不在 cmake 目录里）
  装进 `/usr/share/locale/<lang>/LC_MESSAGES/`；再用**宿主**的 `localedef` 生成
  `ES_LOCALES_TO_GENERATE`（默认只有 `zh_CN`，每个约 3.1 MB）。宿主 glibc 2.39 生成的 locale
  在板上 glibc 2.43 能直接用（实测：`locale -a` 列出 `zh_CN.UTF-8`，gettext 返回中文）。
  catalog 数为 0 时 `die`，避免"宿主少了 msgfmt 就静默出英文镜像"。
* `es_settings.cfg` 默认带上 `<string name="Language" value="zh_CN" />` —— 就是用户在菜单里
  选中文时 ES 自己会写的那一行，所以之后用户改语言不会被这个默认值覆盖。
* `r36-es` 新增 `apply_language()`：读 es_settings.cfg 的 `Language`，导出
  `LC_MESSAGES=<lang>.UTF-8` 和 `LANGUAGE=<lang>`。**只设 LC_MESSAGES**，不动 LANG/LC_ALL，
  于是 `LC_CTYPE` 保持 `C.UTF-8`，系统其余部分对字符的判断不变。locale 没生成时打印一行
  说明并退回英文，不静默。

汉字字形不用额外操心：`Font.cpp:278-285` 的 fallback 列表第一个就是
`:/DroidSansFallbackFull.ttf`（`resources/` 里有），中日文都落到它上面。

**目视确认（2026-10-09，作者）**：板子上 ES 界面是简体中文。程序侧证据是 `/proc/<pid>/environ`
里的 `LC_MESSAGES=zh_CN.UTF-8`、`es_settings.cfg` 的 `Language`、以及 35 个 catalog；屏幕上的
文字只能靠眼睛，这一次已经对上。

两个使用上的事实：**换语言要重启 ES 才生效**（gettext 的 locale 在启动时就定了，菜单里选完
不会当场变）；`GuiMenu.cpp:1557` 在 `HAVE_INTL` 下会置 `exitreboot`，但只有
`--exit-on-reboot-required` 才会真的退出（`ExitOnRebootRequired` 默认 false，
`Settings.cpp:144`），本仓库没传这个参数，所以只弹"需要重启"的提示。


# 电量显示 0%：ES 按**名字**找电池，而这块板子叫 `rk817-battery`（2026-10-09 实测）

现象：进 ES 后电池图标显示 0%，但机器明显有电。**原因和之前 `r36-status-screen` 那个
`batt: ?%` 是同一个坑的第二次出现**——主线内核把这路 fuel gauge 注册成 `rk817-battery`，
没有通用的 `battery` 别名。

`es-core/src/utils/Platform.cpp:430-448` 的 `queryBatteryInformation()` 是**按设备名的子串**
挑电池的：`"/bat"`（注意带前导斜杠，所以只有 legacy 的 `.../power_supply/battery` 能命中）、
`qcom-battery`、`qcom-battmgr-bat`、`fuel`、`charger`。板上实测：

```
rk817-battery   type=Battery  status=Full  capacity=100  charge_now=2867000  current_avg=7224
rk817-charger   type=USB      online=1     （没有 status 文件）
```

`rk817-battery` 里是 `-battery` 不是 `/bat`，**一条都不匹配**。失败的方式很讲究，正好凑出
"0% 而不是'没电池'"：`batteryRootPath` 留空 → `batteryCapacityPath` 从未被赋值（还是空串）→
进了 fuel-gauge 分支，可 `batteryCurrChargePath` / `batteryMaxChargePath` 也都是空串，那个
`if` 直接把整段计算跳过 → `ret.level` 保持结构体默认值 **0**（`Platform.h:58`）。
而 `hasBattery` 仍然是 `true`，因为 `"charger"` 确实命中了 `rk817-charger`。于是屏幕上是一个
**画出来了、读数 0%** 的电池，而不是"没有电池"。

修法：名字全部落空之后，改为读每个设备自己的 `type` 文件、取内容等于 `Battery` 的那个——
和 `r36-status-screen` 在这块板子上已经验证过的做法一致。补丁在
`packages/ui/emulationstation/patches/0101-r36max2-battery-match-by-type-not-name.patch`，
由 `scripts/unpack` 自己的 `${PKG_DIR}/patches/*.patch` 机制应用（构建日志里是
`APPLY PATCH (common)`）。

**这个 bug 的验证方式值得记下来**，因为它原来完全静默：修复前那段分支根本不执行，
所以不产生任何日志，"日志干净"不能证明任何东西。要拿证据就得把它变成一个可观测信号——
用一个空文件 bind 覆盖 `capacity`，逼修复后的代码路径必须去读那个确切路径：

| 步骤 | 结果 |
| --- | --- |
| A 基线（capacity 正常可读 = 100） | ES 日志 **0 行**，`Error reading/opening` 0 条 |
| B `mount --bind /tmp/emptycap …/rk817-battery/capacity` | 日志 30 行，**19 次** `Error reading: /sys/class/power_supply/rk817-battery/capacity` |
| C `umount` 撤销 | 日志回到 **0 行**，`stray mounts over sysfs: 0`，capacity 恢复 100 |

B 是决定性的：只有修复后的代码才会以那个路径打开容量文件（修复前 `batteryCapacityPath`
是空串，这行日志不可能出现）。测试脚本 `F:\r36-build\batt-proof.sh`，属临时挂载，C 步已撤销。

顺带记一个框架缺陷（已防护）：`scripts/unpack` 应用 `patches/*.patch` 时**不检查 `patch`
的返回码**，而 `scripts/build` 的 `BUILD_CLEANUP_INSTALL` 随后会删掉失败时留下的 `*.rej`。
也就是说上游一挪代码、补丁静默失效，构建照样绿。所以 `post_patch()` 里 grep 了插入内容
的标记串，打不上就 `die`。

**目视确认（2026-10-09，作者）**：屏幕上电量就是 100%。这一条上程序侧和眼睛侧结论一致——
bind-mount 实验已经证明 ES 读的是 `rk817-battery/capacity`（值 100），现在渲染出来也对。
