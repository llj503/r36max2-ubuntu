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
- 脚本与文档里 **146 处** 指向旧目录的路径引用被自动改写（`build/x`、`/mnt/e/ubuntu/build/x`、
  `board/x`、`out/x`、`shots/x` 五类），只有确实对应"已移动的被跟踪文件"才改写；README 里
  5 处通配写法（`build/v20-*.sh` 这类）手工修正。
- `.gitattributes` 的 linguist 条目、`.gitignore` 的忽略规则跟着新路径更新。
- 全部 `.sh` 过 `bash -n`、全部 `.py` 过 `py_compile`，0 失败。
- 未被改写的两类路径是**故意的**：
  1. `build/` 仍然是脚本的本机 scratch 目录（第三方源码、CMake 中间产物、`wifi-cred.txt`），
     只是不再存放仓库文件；
  2. `/mnt/e/ubuntu` 是原作者构建机上的盘符，换机器请自行替换；`archive/` 里的一次性脚本
     没有逐条改写它们写死的输出目录。
