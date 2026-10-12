# 模拟器这一层（RetroArch + 自编 libretro 核）

[← 返回 README](../../../README.md)

v21 的模拟器层是**从源码交叉编译**的：`packages/libretro/*/package.mk` 每个核一份，
pin 到具体 commit + SHA256，由框架构建后装进 `/usr/lib/libretro/`。Ubuntu 仓库里有
RetroArch 本身（resolute 是 `retroarch 1.22.2+dfsg`），但**没有任何 libretro 核心包**
（`apt search libretro` 回答 "No such package"），所以核只能自己编 —— 抄现成 .so 的路线
只在闭源/无法构建的东西上才考虑，目前一个都没用到。

参考过的三份外部实现：`lcdyk0517/arkos4clone`（同 SoC 的 prebuilt-rootfs 仓库，不是构建
脚本仓）、`batocera-linux/batocera.linux`、`AveyondFly/distribution_rocknix`。arkos4clone 的
`es_systems.cfg` 有 135 个系统，**不能直接拿来用**：它依赖 ArkOS-ES 的 `%GOVERNOR%` 宏和
`sudo perfmax/perfnorm` 辅助命令，路径也是 `/home/ark`。

## 现在装了哪些核，各自是怎么编出来的

| 系统 | 核（`/usr/lib/libretro/`） | 上游 pin | 构建方式 | 这一步真正的坑 |
| --- | --- | --- | --- | --- |
| nes | `fceumm` | `7a542dab` | `make -f Makefile.libretro platform=unix` | `platform=linux`/`linux-aarch64` 这些 token 它不认识，会掉进 Windows 分支去链 `.dll`，最后死在 `R_AARCH64_ADR_PREG_PG_HI21` |
| snes | `snes9x2010` | `fe690dd3` | 同上 | — |
| gb / gbc | `gambatte` | `d9d6cd06` | 同上 | — |
| gba | `mgba` | `7a12d6d4` | CMake：`-DBUILD_LIBRETRO=on -DSKIP_LIBRARY=on -DBUILD_LTO=OFF` | mgba 自带 `BUILD_LTO` 开关，我们的交叉 gcc **没有编 LTO 支持**，不关就 `cc1: error: LTO support has not been enabled` |
| gba | `vba_next` | `788192f2` | `Makefile.libretro` | — |
| psx | `pcsx_rearmed` | `c8816799` | `Makefile.libretro` | 这棵树带 `./configure`，框架会给它建一个 out-of-tree 构建目录并在里面跑 `make_target()`，所以必须 `cd ${PKG_BUILD}`，否则 `-f Makefile.libretro` 找不到文件 |
| dreamcast | `flycast` | `4e3e2823` | `make -f Makefile platform=arm64 AS=$CC MFLAGS=-mno-outline-atomics HAVE_OPENMP=0 HAVE_VULKAN=0` | 三处见下 |
| saturn | `mednafen_saturn` | `65f05fa6` | `make -f Makefile platform=unix LTO=0` | 这个 Makefile 默认打开 `-flto=auto -fipa-pta`，同上必须关掉 |
| gba | `gpsp_ezode` | `b4918c36` | `make platform=arm64` | 见下，和 flycast 是同一类坑但更阴：`platform=unix` 用**构建机**的 `uname -a` 决定 JIT |
| arcade / neogeo / fbneo / cps1 / cps2 | `fbneoplus` | `8ebb4eea` | `cd ${PKG_BUILD} && make -C src/burner/libretro platform=aarch64` | 第一个坑是 `-C` 相对路径：`make_target()` 不在 `${PKG_BUILD}` 里跑，所以少了 `cd` 就 `src/burner/libretro: No such file or directory` |

gpsp 的坑读代码才能看见，编出来的东西不会报错：`platform=unix` 分支（Makefile:23-34）拿
`$(shell uname -a)` —— **构建机**的 —— 去判断 dynarec，在 x86-64 的 WSL 上它命中
`CPU_ARCH := x86_32`，于是把 `x86/x86_stub.S` 塞进 SOURCES_ASM 让 aarch64 的 gas 去汇编 x86
指令；而它唯一一条自动走 arm64 JIT 的路（Makefile:61-69）要求 `CROSS_COMPILE` 里出现字面量
`webos`。所以只能用 `platform=arm64`（Makefile:380-388：`CPU_ARCH := arm64`、
`HAVE_DYNAREC := 1`、`MMAP_JIT_CACHE = 1`）。核本身编不编 dynarec，产物都是 aarch64、都能
"编译成功"，唯一的区别是慢 —— 配方因此不去 `nm` 符号（`link.T` 只导出 `retro_*`，装好的
`.so` 又被框架 strip 掉），而是断言 `arm/arm64_stub.o` 存在且 `arm_stub.o` 不存在：
Makefile.common:35-44 只在 `CPU_ARCH=arm64` 时追加 `arm64_stub.S`，32 位路径追加
`arm_stub.S`，解释器两个都不追加，而 Makefile:584 把 `SOURCES_ASM` 变成源码同名的 `.o`。

flycast 的三个坑值得单独记，因为它们都不是"参数写错"而是**默认值在交叉编译下是错的**：

1. **`platform=arm64`，不是 `platform=unix`。** unix 分支把 `uname -m` 的结果（构建机是
   x86-64）当 `WITH_DYNAREC`，会给 aarch64 目标编出 x86 dynarec；而且它强制 `HAVE_VULKAN=1`，
   把 vendored glslang 整个拖进来。`arm64` 分支显式 `WITH_DYNAREC=arm64`、`FORCE_GLES=1`
   （本机是 Mesa/Panfrost 的 GLES 3.1，Mali-G31，从 RetroArch 自己的日志量的），Vulkan 保持关闭。
2. **`AS` 必须是编译器驱动。** arm64 分支把 `$(CFLAGS)` 原样塞进 `ASFLAGS`，
   于是 `aarch64-...-as` 会收到 `-DTARGET_LINUX_ARMv8` 和 `-frename-registers`，它不认识。
3. **atomics 只能内联。** 这个 Makefile 自己 `CFLAGS :=`，框架的 `-mno-outline-atomics`
   传不进去，链接就找 `__aarch64_swp4_acq_rel`；而 sysroot 里只有 `libatomic.so.1`
   没有 `-latomic` 的链接名。`MFLAGS` 是它 arm64 路径上唯一没被复写的变量（只有 x86 分支
   会 append），并且编译规则同时把它拼进 C 和 C++ 命令 —— 所以标志走这里。Cortex-A35
   有 LL/SC exclusive，内联出来是对的，只是没有 LSE。

## 启动链：为什么中间要有一个 `r36-play`

```
ES 的 <command> = /usr/local/bin/r36-play %ROM%
   → ES-DE 看见命令里没有 %EMULATOR%/-core，就自己追加 " -emulator retroarch -core <核名>"
      （es-app/src/FileData.cpp:553-557）
   → r36-play 吃掉这两个参数（RetroArch 会把 "-emulator" 当非法参数退出），把核名变成
      /usr/lib/libretro/<核>_libretro.so
   → exec retroarch -c ~/.config/retroarch/retroarch.cfg --appendconfig=/etc/r36/retroarch.cfg \
          --fullscreen -L <那个 .so> <游戏>
```

两个必须成立的条件，都是实测出来的：

- **`/etc/r36/retroarch.cfg` 必须存在**，否则游戏**有画面没声音**：这台机器没有 PulseAudio，
  而 RetroArch 的默认音频驱动就是 pulse。同一个核、同一个游戏，加上
  `audio_driver = "alsa"` 之后 `Initialized PLAYBACK device` 才出现。
- **`<core>` 的名字必须等于已安装库的文件名主干**（`flycast`、`mednafen_saturn`、
  `vba_next`，注意下划线）。`scripts/image` 现在会把装好的 cfg 逐条对着镜像核：每个
  `<system>` 声明的每个 `<core>` 都要有对应 `.so`，每个 `<path>` 目录都要存在且非空 ——
  因为这两种错都**不会**让打包失败，只会让板子上要么启动即退，要么整个系统在 ES 里无声消失。

`r36-play` 还留了一份"没给 `-core` 时按 ROM 所在目录推断"的默认表。加它不是为了好看：
第一次六核验证时，脚本在 ES 外面手工启动，六个系统全部 `rc=4`，而这跟核本身一点关系都没有。

## 实机成绩（64 GB 卡，v21，2026-10-08）

测法要先把两件事分开：

- **日志里的 `Geometry: ... FPS: 60` 是游戏的标称刷新率**，满速和被限速到 25% 长得一模一样，
  不能当成绩用。
- **`retroarch --max-frames=N` 让 RetroArch 跑满 N 个模拟帧后自己退出**，所以墙钟时间除以 N
  就是真实速度。但**一次测量仍然不够**：600 帧在 nes 上是 13.4 s，在 dreamcast 上是 14.7 s，
  而 13.4 s 里有约 3.4 s 是启动（建 GL context、装核、读 BIOS），八个系统单看一次都会得到
  "44 fps"，包括明明满速的 nes。所以每个系统跑两点（600 与 1800 帧），**取斜率**
  `(1800-600)/(t2-t1)`，把常数项消掉。

游戏全部来自游戏包里的**真游戏**，不是手搓的测试 ROM。

**测量前必须先把 ES 停掉。** ES 和 RetroArch 都要 DRM master，ES 在前台时 RetroArch 拿不到
模式设置，日志是 `[KMS] Error when switching mode` → `Cannot open video driver` → 然后在自己的
错误路径里 **SIGSEGV（rc=139）**。这个 139 看起来完全像是"核心崩了"，实际上核心一行代码都没跑。
第一次 N64 测量就是这么被废掉的（`r36-es.service` 装上之后每次开机都有 ES 在前台，所以这个坑
以后每次都会踩）：

```sh
systemctl stop r36-es ; fuser /dev/dri/card0   # 必须是空的
```


| 系统 | 核 | 游戏 | 标称 | 实测持续 | 结论 |
| --- | --- | --- | --- | --- | --- |
| nes | fceumm | 宝石方块.zip | 60.10 | **59.82 fps** | 满速 |
| snes | snes9x2010 | 超级马里奥医生.zip | 60.096 | **60.31 fps** | 满速 |
| gb | gambatte | 打砖块.zip | 59.73 | **59.89 fps** | 满速 |
| gbc | gambatte | 骰子方块.zip | 59.73 | **60.60 fps** | 满速 |
| gba | mgba | 数独.zip | 59.73 | **60.00 fps** | 满速 |
| gba | vba_next | 数独.zip | 59.73 | **62.13 fps** | 满速 |
| psx | pcsx_rearmed | 大航海时代外传[简].PBP | 59.82 | **59.94 fps** | 满速 |
| dreamcast | flycast | 月华剑士2 汉化版.cdi | 60 | **58.85 fps** | 基本满速 |
| dreamcast | flycast | Capcom vs SNK 2.chd | 60 | **55.48 fps** | 92%，个别场面掉帧 |
| saturn | mednafen_saturn | 棉花小魔女 日版.chd | 60 | **14.13 fps** | 不可玩 |
| saturn | mednafen_saturn | 大航海时代2[简].chd | 60 | **15.41 fps** | 不可玩 |

这张表是**从刷好的镜像启动的那张卡**上量的（2026-10-09）。前一天在手工部署的同款文件上也量过
一遍，逐项差都在噪声内（nes 59.84/59.82、dreamcast 59.05/58.85、saturn 14.22/14.13），
所以核的表现与"文件是拷进去的还是装进去的"无关。

两轮共 20 次启动全部 `rc=0`、`errors=0`、`Initialized PLAYBACK device` 至少一次。DC 的日志里有真正的
启动信息（`[BOOT]: Product number: T1249M`），Saturn 认出了盘（`Game ID is: T-9906G`、
`This is a Saturn disc`、`Disc Region: "Japan"`）。

**而且是看得见的**：`--max-frames-ss --max-frames-ss-path=<png>`（两个开关都要给，只给路径会
静默什么都不产出）让 RetroArch 用自己的读回路径出图 —— 这条路上 `--verbose` 拿不到的画面证据
终于有了，而且和"抓 `/dev/fb0` 抓不到 ES"不冲突（见 [EMULATIONSTATION.md](EMULATIONSTATION.md)）：

![Dreamcast：flycast 跑月华剑士2 汉化版，第 900 帧——SEGA 授权画面加上汉化组水印都在](images/dreamcast-flycast-boot.png)
![Saturn：satune 跑棉花小魔女，第 600 帧 boot 到 SEGA 授权画面，只是只有 14 fps](images/saturn-satune-boot.png)
![PlayStation：pcsx_rearmed 跑大航海时代外传 PBP，KOEI 开场](images/psx-pcsx-rearmed-boot.png)

**一个只在脚本里才会踩到的点**：flycast 对 **SIGTERM 的响应不可靠** —— 同一张卡、同一个游戏，
2026-10-08 那次 `timeout -k 5 12 r36-play <dc 游戏>` 是 `rc=137`（TERM 没生效，靠 KILL 收掉），
第二天同一行命令是 `rc=124`（正常退出）。所以任何"跑 N 秒然后杀"的写法**必须带 `-k`**，
不能假设 TERM 够用。RetroArch 自己的退出路径没这个问题：`--max-frames` 每次都 `rc=0` 干净退出，
菜单里的 Quit 走的是同一条路。也就是说这是**测量脚本**的坑，不是玩家按退出会遇到的坑。

也就是说：**"能不能加载"这一层全过了；DC 在这台机器上是真能玩的；Saturn 差的是速度，
而速度是这颗 SoC 与这个核（satune 没有 ARM dynarec）的上限，不是配置的疏漏。**


## BIOS：三家要三个不同地方，全是实测出来的

| 需要 | 放哪 | 怎么知道的 |
| --- | --- | --- |
| PlayStation | `/roms/bios/SCPH30004R.bin` | 放进去之前 `pcsx_rearmed` 不启动 |
| Dreamcast | **`/roms/bios/dc/dc_boot.bin`**（子目录！） | 直放 `/roms/bios/dc_boot.bin` 时 flycast 报 `Unable to find bios in /roms/bios/dc/`；补上子目录后它还会往同一目录写 `dc_nvmem.bin` 与 `vmu_save_{A..}1.bin`，所以这是"模拟器的存档区"而不只是查找路径。`packages/rk3326/es-launcher` 已经在镜像里建好这个目录 |
| Saturn | `/roms/bios/sega_101.bin`（不是 `saturn_bios.bin`） | 只有 `saturn_bios.bin` 时报 `Cannot open BIOS file "/roms/bios/sega_101.bin"` |

## 加一个新核就是这四步，少一步的表现都不一样

1. `packages/libretro/<核名>/package.mk`：`PKG_TOOLCHAIN="manual"`，pin commit + SHA256
   （**哈希要按 recipe 真正抓的那个 URL 算**：GitHub 把顶层目录名烧进 tarball，branch 形式和
   commit 形式对同一棵树给出不同哈希），`make_target()` 里 `cd ${PKG_BUILD}`，
   `makeinstall_target()` 把 `<核>_libretro.so` 装进 `/usr/lib/libretro/` 并在装之前
   `[ -f ] || die`。
2. `packages/virtual/image/package.mk` 的 `PKG_DEPENDS_TARGET` 加这个名字 —— 否则它只是
   `make build PKG=` 能编出来的一个文件，进不了镜像。
3. `packages/rk3326/es-launcher/es_systems.cfg` 加 `<system>`，`<core>` 写**库文件名主干**；
   如果希望不经过 ES 也能手工启动，再往 `r36-play` 的默认表里加一行。
4. `make image`。打包阶段会把第 3 步逐条对着镜像核（core 有没有 `.so`、path 目录在不在），
   所以前三步里任何一步漏了都会在这里失败，而不是在板子上"没声音/没系统/启动即退"。

## 不走 RetroArch 的两个：OpenBOR 与 ONScripter

上面四步是给 libretro 核的。这两个是**独立引擎**，`<command>` 直接指自己的 wrapper，
没有 `<emulators>`/`<core>`，因为程序本身不是核：

| | OpenBOR | ONScripter |
| --- | --- | --- |
| 配方 | `packages/emulators/openbor-ff` | `packages/emulators/onscripter` |
| 上游 pin | `AveyondFly/openbor-fflns` `5cac6523`，tarball 189 MB，sha256 `2e2ff887` | `YuriSizuku/OnscripterYuri` `08f744b3`，sha256 `7d0b640b` |
| 游戏长什么样 | `/roms/openbor/*.pak`（游戏包里 30 个） | `/roms/onscripter/<游戏目录>/*.ons` 标记文件 |
| 为什么必须包一层 | 引擎**没有 rom 参数**：`sdlport.c:30` 把游戏目录硬编码成 CWD 旁的 `Paks`，`menu.c:522` 找不到就打印 `No Mods In Paks Folder!`。所以 wrapper 清空 `Paks/` 里的符号链接、只链本次这一个（连同 `*.pak.0*` 分卷），再 `cd` 过去执行 | 引擎的 root 参数吃的是**目录**不是脚本（`onscripter_main.cpp:370`），而 ES 给的是标记文件，所以 wrapper 取它的 `dirname` |
| 配置落点 | `/roms/.config/openbor`（在 ROM 分区上，用户能自己找到存档；同时在每个 `<path>` 之外，`Paks/` 的符号链接和引擎自建的 `Logs/` 不会被当成游戏扫进来） | 存档由引擎写进游戏目录本身 |
| 手柄 | 打 0001 号补丁后输入走 `SDL_GameController`（补丁把 `SDL_JoystickOpen` 从 `engine/sdl/control.c` 里**换掉**而不是并存，配方据此断言：两条 API 同时活着会每个键触发两次且没有任何报错）。因此不需要参考发行版那套 `gptokeyb` 假键盘；SDL 初始化会读 CWD 的 `gamecontrollerdb.txt`，wrapper 把 PortMaster 那份 r36max2 映射链过去 | 引擎自己处理 SDL 事件，`-enc:gbk` 是写死的默认值（编码错了照样"跑起来"，只是满屏乱码） |

两个引擎的 `make` 参数也各有一个只能读代码才发现的点，都写进配方的注释里了：

- OpenBOR：`-Werror` **不用去 sed**（参考配方 sed 它，但这个 commit 的 Makefile 里唯一一处
  在 513 行的注释里，516 行的活命令行没有它）；`STRIP` 走 `NO_STRIP=1`（Makefile:259 的
  Linux 分支是裸 `strip`，即宿主 amd64 的 strip 去剥 aarch64 ELF），编完由配方用交叉
  binutils 剥；`pkg-config sdl2 --cflags` 在 519 行被 shell 出来，框架
  `config/functions:218-235` 已经为 target 构建导出了完整的交叉 pkg-config，
  所以**不要**在配方里再声明一遍（我第一版就是这么写的，反而比框架的窄）。
- ONScripter：它的 libretro 目标（`src/onsyuri_libretro`）把 SDL2/SDL_image/SDL_mixer/
  SDL_ttf/bzip2/lua 六个依赖**以 submodule 形式 vendored 进去自己编**，而 GitHub 的 archive
  不解 submodule（实测六个目录 `files=0`）。选它就要再 pin 六个上游，所以走 standalone
  分支（CMakeLists.txt:46-70），代价只是 rootfs-apt 里多五个 `-dev` 包。

**当前状态**：`rootfs-apt` 补的那批 `-dev` 包（`libsdl2-gfx-dev libvpx-dev` +
`libsdl2-ttf-dev libsdl2-image-dev libjpeg-turbo8-dev libbz2-dev lua5.4-dev`）正在重新拉闭包，
两个引擎配方已经写好但**还没编过**，更没进过卡。`packages/emulators/*/*/sources/` 之所以能
进 git，是因为 `.gitignore` 里那条 `sources/` 收窄成了 `/sources/` —— 原来那条不带锚点，
把包自己的 `sources/` 也吞了：wrapper 文件躺在磁盘上 git 看不见，只有推完之后在构建机上
`install` 那行才会暴露"文件不存在"。

## 还没做

- **N64：核在树里，系统条目暂时摘掉了。** `packages/libretro/libretro-parallel-n64` 能编出来，
  aarch64 dynarec 也确实在二进制里，但三个真游戏全部在第一帧之前 SIGSEGV，内核寄存器显示
  **`pc = 0x0`**（通过空函数指针调用），位置在视频插件启动处。本机 GL 上下文是 GLES 3.1，
  而默认插件 GLideN64 要桌面 GL 的入口点。试过 `cpucore=interpreter`、换 RSP、换
  `gfxplugin=gles2n64` 都同样崩；`HAVE_GLIDEN64=0` 则链不过。修好之前 `es_systems.cfg` 里
  留着注释说明，恢复只需把那段加回来。详见 [KNOWN-ISSUES.md](KNOWN-ISSUES.md)。
  **不要用"全局强制桌面 GL 上下文"去修**，那会牵动另外 8 个已经正常的核。
- **更重的平台**（PS2 / Switch / 3DS / Wii）：1 GB RAM + Mali-G31 这条线不用试，
  arkos4clone 的 32 位 `retroarch32` 核那一套在本镜像里也跑不了（ABI 是 ARMv7）。
- Saturn 换 `Yaba Sanshiro`（arkos4clone 用它是 standalone SDL 程序，有自己的配置与输入映射）
  能快一些，但它不进 libretro 这条路 —— 要单独接 `<command>`，还没决定值不值。

## 一个已经消掉的 ERROR：`menu_driver`

`/etc/r36/retroarch.cfg` 原来写 `menu_driver = "null"`，于是**每次启动都有一条
`Unable to init menu driver.`**。实测这个 build 接受的取值：`null` → 1 条错误，
`ozone / materialui / rgui / xui` → 0 条。选 `rgui`：它吃手柄方向键，所以游戏内浮层
（核心选项、着色器、存档状态、退出）在这台没有键盘的机器上是**能用**的 —— 当初写 "null"
的理由（"RGUI 需要键盘才逃得出来"）是错的。资源在
`/usr/share/libretro/assets`（Ubuntu 的 `retroarch-assets` 装在这里，不在
`/usr/share/retroarch`），cfg 里现在也写了 `assets_directory`。

