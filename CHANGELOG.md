# R36 Max 2 (RK3326) —— 目录结构对齐 ROCKNIX/distribution

本次重排把只有一个 `build/`（446 个脚本平铺）的仓库，按角色拆开，目录命名对齐
[ROCKNIX/distribution](https://github.com/ROCKNIX/distribution)：

| 新位置 | 原来在哪 | 是什么 |
| --- | --- | --- |
| `projects/r36max2/dt/` | `board/` | 板级设备树与 DRAM timing |
| `projects/r36max2/patches/` | `build/`、`build/joypad/` | 内核/驱动补丁集 |
| `packages/<名字>/` | `build/` 里的 `r36-*`、`weston.*`、`es-input-*.cfg` | 装进 rootfs、跑在板子上的程序与 systemd 单元 |
| `scripts/` | `build/` | 宿主机流水线：取内核、打补丁、编译、装 rootfs、打包镜像 |
| `tools/<子系统>/{diagnostics,runtime,verify}/` | `build/` | 调试仪器。只读观测 / 改变板子状态 / 通过-失败判定 |
| `config/rootfs/` | `build/99-r36-power.conf` | 直接落进 rootfs 的配置 |
| `distributions/` | `out/*.sha256` | 每一版镜像的 sha256 与发布记录 |
| `documentation/PER_DEVICE_DOCUMENTATION/r36max2/` | 根目录与 `out/` 的 `.md`、`shots/` | 移植方案、刷写与首启、上传步骤、验收图 |
| `archive/` | `build/` | 被取代的历史版本，见下 |

## 兼容性处理

- 477 个文件用 `git mv` 移动，历史可追。
- 脚本与文档里 **171 处** 指向旧目录的路径引用被自动改写（`build/x`、`/mnt/e/ubuntu/build/x`、
  `board/x`、`out/x`、`shots/x` 五类），只有确实对应"已移动的被跟踪文件"才改写；README 里
  5 处通配写法（`build/v20-*.sh` 这类）手工修正。
- `.gitattributes` 的 linguist 条目、`.gitignore` 的忽略规则跟着新路径更新。
- 全部脚本过语法检查（`make lint` → `scripts/lint.sh`：373 个 shell、36 个 python，0 失败）。
- 新增 `make lint` 与 `.github/workflows/lint.yml`：CI 只做语法与目录约定检查，
  真正的构建需要 WSL + aarch64 交叉工具链 + 一块真机，不适合放进 Actions。
- 未被改写的两类路径是**故意的**：
  1. `build/` 仍然是脚本的本机 scratch 目录（第三方源码、CMake 中间产物、`wifi-cred.txt`），
     只是不再存放仓库文件；
  2. `/mnt/e/ubuntu` 是原作者构建机上的盘符，换机器请自行替换；`archive/` 里的一次性脚本
     没有逐条改写它们写死的输出目录。

## README 拆分（同一天的第二步）

README 原本 640 行，把所有移植细节堆在一个文件里。按 ROCKNIX 的做法（短首页 +
`documentation/PER_DEVICE_DOCUMENTATION/<设备>/` 放正文）拆成：

- `README.md` 91 行：简介、状态表、文档索引、目录结构。
- `documentation/PER_DEVICE_DOCUMENTATION/r36max2/` 新增 14 篇主题文档：
  `HARDWARE` `BUILD` `FLASH` `DEBUGGING` `GPU` `WAYLAND` `JOYPAD-BRIDGE` `OSK`
  `EMULATIONSTATION` `WIFI-AND-SHARING` `KERNELS` `KNOWN-ISSUES` `LICENSING` `SECURITY`（`.md`）。

拆分是**逐字节切片**，没有改写或概括任何一段正文；只有三类改动：标题从 `##` 升为 `#`、
图片链接改成同目录的 `images/001.jpg`、以及"见上一节/见下文"这类相对指向改成跨文件链接。
指向 README 章节的其它引用（`Makefile`、`archive/README.md`、`distributions/README.md`、
`scripts/pack-v20.sh`、`scripts/apply-wayland.sh`）跟着改指主题文档。

顺手修掉两个既有坏链：`刷写与首启说明.md` 里指向已不存在的 `out/` 的链接，以及一个写死
`/E:/ubuntu/...` 的本地路径链接（改为指向 `distributions/` 的校验记录）。全仓 markdown
链接检查：0 坏链。

