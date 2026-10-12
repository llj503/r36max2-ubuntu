# distributions/ —— 发布记录

镜像本体（约 400 MB 压缩后）不入库：仓库只放每一版的 sha256。**也不作为 Release 附件
公开上传**——镜像里含 AIC8800DC 的厂商固件 blob，分发它等于分发别人的二进制，所以想要
镜像就按 [BUILD.md](../documentation/PER_DEVICE_DOCUMENTATION/r36max2/BUILD.md) 自己构建，
产物落在 `target/`，再用下面这列哈希对一遍。

**同一版镜像重建一次哈希就变一次，而它记在两个地方**：下面这张表和同名的
`<文件>.sha256`。2026-10-08 发现这两处已经不一致了（`6a472e1` 只改了 `.sha256`，表里还是上一版
的哈希），所以改的时候**两处一起改**。

| 文件 | sha256 |
| --- | --- |
| `r36max2-ubuntu-v2.img.xz` | `a3b0ccf69faea8747351a91a7efdc48573644d74a1e69222edacedb4514c0b81` |
| `r36max2-ubuntu-v3.img.xz` | `273b24b07001db783b0124eed8e51a7798c14959e33d741c18e29bf0730c01ed` |
| `r36max2-ubuntu-v4.img.xz` | `cb958357dd2be58224eedb8e34d15df762c94f3c03f29a3023f602b6dabd324b` |
| `r36max2-ubuntu-v5.img.xz` | `94d2ffba82ec810c1950697c29046e20e869482afdea7c88fe8d0a3828e48b72` |
| `r36max2-ubuntu-v6.img.xz` | `0c70f2b3fbc8c078691b4a553ce52d0ba35eabcc1b47dc245e61ee4c349e3acd` |
| `r36max2-ubuntu-v7.img.xz` | `83b29fe491f7768d855ef8ec36477fdd98eb5dab47f1afdf80c998e3fe417177` |
| `r36max2-ubuntu-v8.img.xz` | `8da7a9f31aa440ebb6438644aeb3a5a1027a39ff3c00867b3857ccb6e57dbabf` |
| `r36max2-ubuntu-v9.img.xz` | `237502d2ab4725b97825a83ed43a8c0438953fed95e883b390849f06df731a89` |
| `r36max2-ubuntu-v10.img.xz` | `2e58e8856f8547c64a01b7be9ee1bfe4abcc57002f96831b6e0d3cc549d7a122` |
| `r36max2-ubuntu-v11.img.xz` | `1b71f49629681fe41c1e4fee5cbe20cade7c67fc08ab16258cd4e32d1046f5d9` |
| `r36max2-ubuntu-v12.img.xz` | `ef96e54aaa579a593692264d5dedb79017802668ebb0fc171153322074cd003d` |
| `r36max2-ubuntu-v13.img.xz` | `2bec091285eb59e3dc51f5c4691f89ddb1f7228a69501ef3721fe3cc61a73be7` |
| `r36max2-ubuntu-v14.img.xz` | `ae1a938a0f97c7221a2671124b71be8cbe25f2b525d37ec303a4dc3be31a605d` |
| `r36max2-ubuntu-v15.img.xz` | `30af53c3474e36eefada0e5d7c03627fb30585cd74c1e99081e556b8bbef7dfb` |
| `r36max2-ubuntu-v16.img.xz` | `6e19d6068c60aa1d475009b1b7bb6df39ba898d1a2d43f5ba721ffa478471ee3` |
| `r36max2-ubuntu-v17.img.xz` | `5290cc9665d40349998b8cf1e210b88f06cd7c19ab134e5e5b90ae58171f269a` |
| `r36max2-ubuntu-v18.img.xz` | `da2a12b30a0bbe4b6a1bc6f48d00f41b8e61ab57f98cf9e690482aade0c71510` |
| `r36max2-ubuntu-v19.img.xz` | `ea1aa41ea33d56b467d2100c333baf8d6c0f55c7cd00b99b63e56a8d018cb282` |
| `r36max2-ubuntu-v20.img.xz` | `da46854618144d70b49d47cf54ad7aa81bbf59922636e2670c4cbb2e2f66a143` |
| `r36max2-ubuntu-v21.img.xz` | `1edb61293e6146761acfbb53c3b7c1587780374ba7c4b84d00ae0f2961133d66` |
| `r36max2-ubuntu-26.04.img.xz` | `c0df67ce40f27392d8a9d94a6016754f747a0dd87a3be2e499362bf0d699b64a` |
| `r36max2-ubuntu-alt-arkosblobs.img.xz` | `360ac81678b1344302844d2e89fea541033692c02577de8a15fb65ad12e968d8` |

**v21 这条哈希（`1edb6129`，2026-10-12 09:28，864,277,788 B）是"当前这棵树产出的镜像"，
没有刷进卡里** —— 卡上跑的还是 `7d5cc138` 那份底子 + 手工补齐的层（下面第三节），因为刷一次就抹掉
那 22.6 GB ROM。真正在屏幕上验过的东西写在最后一节。

从 10-10 到 10-12 下午，v21 打过九次。记全是为了别把"量过的哈希"和"卡在跑的东西"混起来：

| 哈希 | 时间 | 里面是什么 | 状态 |
| --- | --- | --- | --- |
| `7d5cc138` | 10-09 | 电池/guard/i18n 四项修复 | **刷进卡里、开过机** |
| `2ef50cd4` | 10-10 上午 | + PortMaster 那一层 | 被当天下一版取代 |
| `cd4e0362` | 10-10 12:25 | + ES 的 Wi-Fi 菜单 | **别刷这一版**：它的 `wifictl` 会重启 supplicant 且失败不回滚，用户第一次在屏幕上实测就把卡弄到完全离线 |
| `df1ef545` | 10-10 14:40 | 同上 + 改成 `reload_config` / 失败回滚 / 只在国家码变化时 `iw reg set` | 被取代 |
| `3fd93d8b` | 10-10 15:25 | 同上 + Wi-Fi 页面顶部的 **IP地址** 行（`patches/0105`） | 被取代 |
| `6d1a7f2b` | 10-10 16:44 | 同上 + 回滚改用 `remove_network`、加驱动复位 | 被取代 |
| `c8c34754` | 10-12 08:42 | 同上 + 审计行、`status` 字段两种写法都吃 | 被取代 |
| `d68cc9e9` | 10-12 09:06 | 同上 + 连接改成运行时 `add_network`（不再重读文件） | 被取代 |
| `1edb6129` | 10-12 09:28 | 同上 + **`set_network` 这个动词名修对**（`wifictl 83bcff2a`） | 被取代；**卡现在跑的就是这一版的底子** |
| **`0f17e54e`** | 10-12 13:27 | 同上 + **两个新核**（`fbneoplus`、`gpsp_ezode`）**+ 两个独立引擎**（`OpenBOR-ff`、`onsyuri`）+ 各自的 launcher，ES 系统 8 → 16 | **当前这棵树的产物。卡没有刷这一版**（刷一次会带走 26 GB ROM），但这层的内容已经逐个文件写进卡并对过 sha；**仍未上机** |

`0f17e54e` 相对 `1edb6129` 多的一层，全部是模拟器侧（890,895,268 B，比上一版大 26,617,480 B，
主要是 FBNeo 那 70 MB 未压缩的核）：

* 核：`libretro-fbneoplus`（pin `8ebb4eea`，`platform=aarch64`，产物 70,361,112 B，53 个
  `retro_*` 导出，自报名 `FinalBurn Neo`）、`libretro-gpsp-ezode`（pin `b4918c36`，
  `platform=arm64`，1,175,504 B，链接行里有 `./arm/arm64_stub.o` 与 `-DHAVE_DYNAREC
  -DARM64_ARCH`，所以 dynarec 是在的而不是又一个解释器）。
* 引擎：`openbor-ff`（fflns fork，带 0001 SDL_GameController 与 0002 aarch64 两个补丁；
  1,733,800 B）与 `onscripter`（上游 `YuriSizuku/OnscripterYuri`；610,760 B）。
* launcher：`/usr/local/bin/r36-openbor`、`/usr/local/bin/r36-ons`（两个引擎都不吃 rom
  参数，各自要一个包装；`/roms/.config/openbor` 是它们的运行目录）。
* 系统条目 8 → 16：新增 `fbneo neogeo arcade cps1 cps2 openbor onscripter`，gba 多一个可选核
  `gpsp_ezode`。打包自检逐条对过：**每个 `<core>` 都在镜像里有同名 `.so`，每个 `<path>`
  都存在且非空**，日志里 `!!` 计数为 0。

这一版里有三条是**构建过程本身教出来的**，写在
[EMULATORS.md](../documentation/PER_DEVICE_DOCUMENTATION/r36max2/EMULATORS.md)：OpenBOR 的
`-rpath-link`（它的链接命令只看 `$(CFLAGS)`，框架的 rpath-link 在 LDFLAGS 里）、onscripter 的
`-llua`（Ubuntu 没有 `liblua.so`，而 `FindLua` 明明已经报`Found Lua: …/liblua5.4.so`），以及
`MinSizeRel` 会带来的 `-flto`——这个交叉 gcc 没有 LTO，是硬错误。还有一条框架级的：
`calculate_stamp` 现在自己在 `$ROOT` 里算哈希，因为包钩子里一个 `cd` 就能把 stamp 打成
"空输入的哈希"（详见该文件 #46 那段）。


**中间那六版有一个共同点：它们的 `wifictl` 全都连不上第二个网络**，原因不是芯片也不是口令，
而是脚本里用的 `reload_config` / `set network` 两个动词在这台机器的 `wpa_cli` 里**根本不存在**
（正确的是 `reconfigure` / `set_network`），而回话被丢进 `/dev/null`，所以"命令不认识"和
"照办了"在日志里长得一模一样。完整因果和取证过程见
[WIFI-AND-SHARING.md](../documentation/PER_DEVICE_DOCUMENTATION/r36max2/WIFI-AND-SHARING.md)——
这一条值得留在哈希表旁边，因为"看着全绿的六版镜像"和"能用的那一版"差的就是一行回话有没有被读。

`1edb6129` 比 `7d5cc138` 多的两层：

* **PortMaster**（见 [PORTMASTER.md](../documentation/PER_DEVICE_DOCUMENTATION/r36max2/PORTMASTER.md)）：
  pin 住的 `PortMaster.zip`（24,131,471 B，sha256 `6e4fa938…`）+ 两个启动器 + ES 的 Ports 入口 +
  这台板子的两处补丁（`fix_control.py`、SDL 映射行），rootfs 里再多了 apt 装的
  `libsdl2-ttf/image/gfx` 和 `/etc/hosts`。**打包自检当场把它拦下来过一次**：第一遍
  `cp -a overlay/` 把两处补丁放成了 `/usr/config/PortMaster/overlay/…`（多套一层目录），断言直接红，
  所以这个哈希是修好之后重打的那一份。
* **ES 的 Wi-Fi 菜单**（见
  [WIFI-AND-SHARING.md](../documentation/PER_DEVICE_DOCUMENTATION/r36max2/WIFI-AND-SHARING.md)）：
  `/usr/bin/wifictl`（`83bcff2a`，33,177 B，755，十一个子命令含 `recover`）+ `patches/0103`（把入口
  加进非 batocera 分支）+ `patches/0104`（补 `zh_CN` 九个空串）+ `patches/0105`（页面顶部的
  **IP地址** 行，因为 0103 绕开了 `openNetworkSettings()`，而那页长着整棵树唯一的 IP 行）。
  ES 二进制跟着变了两次：`b6b968cd` → `92272ebcc0d181c7…`（0103/0104）→
  **`ca9daf6bda0bc1d3…`**（0105，8,538,312 B）；自检仍然要求镜像与 `install_pkg` 逐字节相同
  （这次两边都是 `ca9daf6b`）。

**卡上没有为了这些层重刷**（刷一次就抹掉那 22.6 GB），是照样补齐的：四个缺的包
`libsdl2-ttf-2.0-0 / libsdl2-image-2.0-0 / libsdl2-gfx-1.0-0 / libwebpdemux2` 用构建机从同一快照
下好的 deb `dpkg -i` 装的（为什么不能 `apt-get install`——它会顺手升 `libblkid1`、撞上
`util-linux` 的精确 PreDepends——见 [KNOWN-ISSUES.md](../documentation/PER_DEVICE_DOCUMENTATION/r36max2/KNOWN-ISSUES.md)）。
现在卡上三个手工件与仓库/镜像逐字节相同：

| 卡上的文件 | sha256(16) | 换下来的原件备份 |
| --- | --- | --- |
| `/usr/local/bin/emulationstation` | `ca9daf6bda0bc1d3` | `/root/emulationstation.pre-wifi`、`/root/emulationstation.pre-ip` |
| `/usr/share/locale/zh_CN/…/emulationstation2.mo` | `604b102148bf97cc` | `/root/emulationstation2.mo.pre-wifi` |
| `/usr/bin/wifictl` | `83bcff2a7493bca9` | `/root/wifictl.pre-reset`（= `b1eadc14`） |

**屏幕上确认过的**（10-12）：设置里那行 **Wi-Fi 网络**、连上在用网络后 **IP地址 行显示真实地址**
（`192.168.0.141`，journal 里同一秒有 `CTRL-EVENT-CONNECTED` 与 DHCP 回话对上），以及
**换到第二个网络 aqk 也连上了并且换了地址**（`192.168.0.106`，conf 里存成第二个块，重启后还在）。

只读挂载 `1edb6129` 的产物复核过（2026-10-12 上午）：镜像里的 `wifictl` 是 `83bcff2a`（33,177 B）
且与仓库副本 `cmp` 逐字节相同，子命令 11 个含 `recover`；**两个在这台机器上不存在的动词
`reload_config` / `set network` 在文件里出现 6 次，逐行查过全部在注释里**（只查第一处就下结论是
我这一周犯过两次的错），正确写法 `set_network`/`reconfigure`/`add_network` 各 4/5/4 次在代码里。
ES 是 `ca9daf6b`（8,538,312 B）与 `install_pkg` 逐字节相同；`zh_CN` catalog 仍是 `604b102148bf97cc`，
`IP地址`、`未连接`、`Wi-Fi 网络` 三个串都在（用 `grep -a`，`strings` 只提 ASCII、看不到中文）。
`/usr/config/PortMaster/` 恰好 `fix_control.py`、`gamecontrollerdb-r36max2.txt`、`release/` 三项，
三个 SDL2 扩展库在，`/etc/hosts` 有 `127.0.1.1 r36max2`，`/lib/modules` 只有 `7.2.9` 且
`extra/` 里 `aic_load_fw.ko` + `aic8800_fdrv.ko` 都在（驱动复位的前提）。
**还有一条证据链要说清**：`0105` 的标记是注释，stripped ELF 里查不到，所以产物侧能证明的只有
"打进镜像的 ES == `post_patch()` 验收过的那份二进制"，而 `post_patch()` 没有那个标记就会 `die`。

## 10-12 下午：两个新核与两个引擎——镜像侧是 `0f17e54e`，卡侧是原地写进去的同一批文件

这一轮是"把卡原地抬上去"，不是刷图（刷一次抹掉 22.6 GB ROM）。写的东西逐个写后读回 sha 比对，
全部是**新增路径**，唯一覆盖的是 `es_systems.cfg`，而它这次**故意没写**（原因见末尾）。

| 卡上新增的文件 | sha256(16) | 字节 |
| --- | --- | --- |
| `/usr/lib/libretro/fbneoplus_libretro.so` | `edf24709f6d3341f` | 70,361,112 |
| `/usr/lib/libretro/gpsp_ezode_libretro.so` | `68ecb835d3f5c51d` | 1,175,504 |
| `/roms/bios/fbneo/neogeo.zip` | `d2d8ab5d5fc5ce41` | 1,760,976 |
| `/roms/openbor/001.pak … 032.pak`（27 个）+ `gamelist.xml` | `001.pak` = `e6e2b4af507585dd` | 3.8 GB |
| `/roms/neogeo` 3 个、`/roms/cps1` 3 个、`/roms/cps2` 2 个、`/roms/fbneo` 5 个 `.7z` | — | ~90 MB |

卡上核数 9 → 11。两核的 `DT_NEEDED`（`libstdc++.so.6 libm.so.6 libmvec.so.1 libgcc_s.so.1
libc.so.6`）在卡的 `/usr/lib/aarch64-linux-gnu` 全部能找到，5 个必需导出也都在，核自报名分别是
`FinalBurn Neo` 与 `gpSP`。`neogeo.zip` 是必须的：FBNeo 在
`<system_directory>/fbneo/<名字>` 找它的 BIOS 与父集（`locate_archive`，libretro.cpp:925-1000），
`system_directory=/roms/bios`，缺它每个 NEOGEO 游戏停在 `Cannot find required rom`。

**这轮只读盘查把两个假设定错了**，记下来免得再当前提用：

1. 卡上那 22 GB **不包含任何街机内容**——`fbneo/ neogeo/ cps1/ cps2/ arcade/` 五个目录当时都只有
   `.keep` 一行，`/roms/openbor` 和 `/roms/onscripter` **根本不存在**，`/roms/bios/` 里只有 `dc/`。
   所以"卡上有游戏可测"对核成立、对街机不成立，街机内容是从 `I:` 包现拷的。
2. 卡上两份 `es_systems.cfg` 的 sha **不一样**：`/etc/emulationstation/` 是 `447bd0d9`，
   `/root/.emulationstation/` 是 `f8f311f3`，而 ES 先读后者——即生效的是 `/root` 那份。以前某轮
   只手改过一边。因此 deploy 必须两份一起写（`deploy-engines.sh` 就是这么做的）。

**写卡已完成**（重插读卡器之后，`deploy-engines.sh` 一次跑过，8 个 payload 全部读回 sha 一致）：
`/usr/lib/libretro/{fbneoplus,gpsp_ezode}_libretro.so`、`/usr/bin/{OpenBOR-ff,onsyuri}`、
`/usr/local/bin/{r36-openbor,r36-ons}`、`/etc/emulationstation/es_systems.cfg` 与
`/root/.emulationstation/es_systems.cfg`（**两份都是 `9eb8a33c`**，之前那处
`/etc 447bd0d9` vs `/root f8f311f3` 的不一致就此消掉），`/roms/bios/fbneo/neogeo.zip`，
以及 `/roms/{openbor,onscripter}`、`/roms/.config/openbor`。旧 cfg 备份在
`/root/es_systems.cfg.pre-engines`。

第一次写卡之所以停在 `ABORT: gate` 上，是读卡器整个从 Windows 的 USB 树上消失
（`usbipd list` 里 `5-2` 不再存在，只剩 persisted GUID），不是 WSL 掉附件那种"说 Attached
但 /sys/block 没有"。门的效果是**那一次一个字节都没写**。

cfg 没有提前写的原因是仓库那份新增了 `openbor` 与 `onscripter` 两个系统，而这两个引擎的二进制
当时还没进卡：ES 会列出 27 个能选中、一按就报 `r36-openbor: not found` 的游戏——这种"看起来装机
成功、点进去全红"的状态比暂时看不见更糟。


**镜像内容只由配方决定，`scripts/image` 里那些自检不改一个字节**，所以加断言不需要重打。
`1edb6129` 是**带着全部断言跑出来的**（PortMaster 四处、三个 SDL2 扩展库、Wi-Fi 菜单的子命令、
回滚形状 + 两个 `.ko` 在场、launcher 两处标记、镜像里的 ES 与 `install_pkg` 逐字节相同、
catalog 35、载体 locale 在），打包当时全绿；上面那段"只读挂载复核"是对着**产物**做的，
不是对着构建目录做的。

校验：把镜像和本目录的 `.sha256` 放同一目录后

```bash
sha256sum -c r36max2-ubuntu-v20.img.xz.sha256
```

内核与镜像的对应关系（[../documentation/PER_DEVICE_DOCUMENTATION/r36max2/KERNELS.md](../documentation/PER_DEVICE_DOCUMENTATION/r36max2/KERNELS.md)）：

- **v2–v19** —— 6.12.79 主线 + Rocknix 三层补丁，EmuELEC 之外的通用 Linux 开发环境
- **v20** —— 双内核：7.2.8 默认、6.12.79 同卡保留（改名即可回退），加 weston 会话、
  摇杆键鼠桥、`r36-osk` 虚拟键盘、无凭据/无主机密钥的发布形态
- **26.04 / alt-arkosblobs** —— 早期 base 变体与用 ArkOS 厂商 blob 打出的对照版

刷机与首启步骤见 `documentation/PER_DEVICE_DOCUMENTATION/r36max2/刷写与首启说明.md`。
