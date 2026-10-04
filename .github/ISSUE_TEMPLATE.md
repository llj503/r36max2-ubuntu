---
name: 问题报告
about: 报告这块板子上的问题（引导、按键、WiFi、GPU、休眠）
title: ""
labels: ""
---

**板子/镜像**
- 设备：R36 Max 2（RK3326，稀范）/ 其他：
- 镜像版本：`distributions/` 里的哪一个（v20?）
- 内核：`uname -a`

**现象**
怎么复现、期待什么、实际什么。

**证据**
- `r36-bootlog` 生成的 `BOOT:\r36-boot.txt`
- `journalctl -b -p err` 的相关片段
- 屏幕的话给 `tools/capture/` 抓的图

**已经试过**
跑了哪些 `tools/<子系统>/diagnostics/` 脚本，输出是什么。
