# archive/ —— 被取代的版本，只作记录

这里的脚本**不在当前流水线（v20）上**。留着它们是因为它们记录了"为什么现在这样做"：
哪一版镜像打过哪些补丁、当时的依赖检查长什么样。

| 目录 | 内容 |
| --- | --- |
| `pre-v20/` | v8–v19 那一代的一次性脚本（`apply-v*`、`accept-v*`、`verify-v*`） |
| `superseded/` | 同名脚本的编号草稿（`build-image2..8.sh`、`pack-image2..4.sh`、`dev-gl2/3.sh`、`k72-deploy2/3/4.sh` 等），保留的是最后一次可用的那一版 |

不要用这里的东西构建镜像 —— 当前顺序在 [../documentation/PER_DEVICE_DOCUMENTATION/r36max2/BUILD.md](../documentation/PER_DEVICE_DOCUMENTATION/r36max2/BUILD.md) 里。
判定标准只有一条：**README 与文档里点名用过的脚本一律留在 `scripts/`**，哪怕文件名带旧版本号
（`apply-v19.sh`、`pack-v10.sh`、`pack-v20.sh`、`build-initrd3.sh` 就属于这种）。
