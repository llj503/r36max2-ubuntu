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

## 只保留当前一套（第三步）

把"活跃目录里同时摆着 v8 到 v20 每一代脚本"的状态收干净：**删掉 363 个文件，仓库从 503 个
降到 140 个**。删除只发生在工作树，历史完整 —— 任意文件可用 `git show 6dd081a:<路径>` 取回，
删除清单见 `git log --diff-filter=D --name-only`。

删掉的是：`archive/` 全部（84）、`tools/` 里没被文档点名的 204 个一次性探测脚本、
`scripts/` 里 75 个不属于当前流水线的脚本（含 v19 的打包器 `pack-v10.sh`）。

留下 140 个的判据（按优先级）：

1. **文档点名的保留**。`documentation/` 与 README 一共引用 54 个仓库路径，它们是移植记录的
   证据来源，删了文档就指向空气 —— 包括 19 个 `tools/`。
2. **从 v20 入口做依赖闭包**。`v20-*.sh`、`apply-wayland.sh`、`pack-v20.sh`、`build-*.sh`、
   `apply-mainline.sh`、`k72-prepare.sh`、`lint.sh`、`git-prepare.sh`、`git-secretscan.sh`
   等 25 个 `scripts/`。
3. `packages/` `projects/` `config/` `distributions/` 全部保留（装进系统的东西、板子定义、
   发布记录本来就只有当前一套）。

一个必须写清楚的事实：**6.12.79 不是遗留支线**。`pack-v20.sh` 里写死
`K6=/root/r36/linux-6.12.79`，v20 镜像同时装 `lib/modules/6.12.79` 和 `lib/modules/7.2.8`
两棵模块树、生成 `boot-612.ini` 作回退项，`v20-stage72.sh` 还要从 6.12 树里取 dtb。
所以 `apply-mainline.sh` 与 `build-all.sh` 是**当前镜像的构建前置**，即使默认内核已经是
7.2.8 也必须留着。要真正只发 7.2.8，那是改打包流程 + 出 v21 的事，不是清理仓库文件的事。

配套改动：`BUILD.md` 重写成单一的 v20 现行流程（原来的"从零构建"五步是 v19/6.12 的走法，
和 v20 顺序并列摆着会误导人）；`apply-v19.sh` 结尾"下一步"提示从 `pack-v10.sh` 改指
`pack-v20.sh`；README 的目录结构去掉 `archive/` 并写清删除物如何取回。

验证：`make lint` 通过（46 shell / 9 python，0 失败）；markdown 链接 0 坏链；剩余 13 处
"指向不存在路径"的匹配逐条看过，全是通配（`scripts/v20-*.sh`）、内核自带的 `scripts/config`、
GitHub codeload 的 `/archive/` URL，以及本变更日志里对历史目录的描述。


