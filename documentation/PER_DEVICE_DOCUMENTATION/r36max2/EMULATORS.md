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

| 系统 | 核 | 游戏 | 标称 | 实测持续 | 结论 |
| --- | --- | --- | --- | --- | --- |
| nes | fceumm | 宝石方块.zip | 60.10 | **59.84 fps** | 满速 |
| snes | snes9x2010 | 超级马里奥医生.zip | 60.096 | **60.47 fps** | 满速 |
| gb | gambatte | 打砖块.zip | 59.73 | **59.34 fps** | 满速 |
| gbc | gambatte | 骰子方块.zip | 59.73 | **59.45 fps** | 满速 |
| gba | mgba | 数独.zip | 59.73 | **60.18 fps** | 满速 |
| gba | vba_next | 数独.zip | 59.73 | **61.03 fps** | 满速 |
| psx | pcsx_rearmed | 大航海时代外传[简].PBP | 59.82 | **60.06 fps** | 满速 |
| dreamcast | flycast | 月华剑士2 汉化版.cdi | 60 | **59.05 fps** | 基本满速 |
| dreamcast | flycast | Capcom vs SNK 2.chd | 60 | **55.48 fps** | 92%，个别场面掉帧 |
| saturn | mednafen_saturn | 棉花小魔女 日版.chd | 60 | **14.22 fps** | 不可玩 |
| saturn | mednafen_saturn | 大航海时代2[简].chd | 60 | **15.41 fps** | 不可玩 |

十一次启动全部 `rc=0`、`errors=0`、`Initialized PLAYBACK device` 至少一次。DC 的日志里有真正的
启动信息（`[BOOT]: Product number: T1249M`），Saturn 认出了盘（`Game ID is: T-9906G`、
`This is a Saturn disc`、`Disc Region: "Japan"`）。

**而且是看得见的**：`--max-frames-ss --max-frames-ss-path=<png>`（两个开关都要给，只给路径会
静默什么都不产出）让 RetroArch 用自己的读回路径出图 —— 这条路上 `--verbose` 拿不到的画面证据
终于有了，而且和"抓 `/dev/fb0` 抓不到 ES"不冲突（见 [EMULATIONSTATION.md](EMULATIONSTATION.md)）：

![Dreamcast：flycast 跑月华剑士2，量到的是真 SEGA 授权画面](images/dreamcast-flycast-boot.png)
![Saturn：satune 跑棉花小魔女，同样 boot 到了 SEGA 画面，只是只有 14 fps](images/saturn-satune-boot.png)
![PlayStation：pcsx_rearmed 跑大航海时代外传 PBP，KOEI 开场](images/psx-pcsx-rearmed-boot.png)

**一个只在脚本里才会踩到的点**：flycast **不响应 SIGTERM**，所以 `timeout 45 r36-play <dc 游戏>`
会一直挂着（实测 `rc=137`，必须 `-k` 才收得掉）。RetroArch 自己的退出路径没这个问题 ——
`--max-frames` 和菜单里的 Quit 都是干净退出（DC 那 11 次 `--max-frames` 全部 `rc=0`）。
也就是说这是**测量脚本**的坑，不是用户按退出会遇到的坑；但任何"跑 N 秒然后杀"的做法都必须
`timeout -k`。

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

## 还没做

- **N64**：`parallel-n64` 链接缺 `-latomic`（和 flycast 同源的问题，还没决定用同一种解法）。
  游戏包里有 n64 目录，随时可以接。
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

