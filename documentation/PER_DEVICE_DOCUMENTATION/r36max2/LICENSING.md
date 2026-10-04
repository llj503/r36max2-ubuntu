# 许可与第三方来源

[← 返回 README](../../../README.md)

- 我自己写的脚本、设备树、demo 与文档：GPL-2.0-or-later（与内核树同源，方便被抄回去）。
- `build/rocknix/`、`build/wifi/`、`build/aic-src/`、`build/joypad/*.tar.gz` 是第三方
  源码/补丁（Rocknix 项目、`radxa-pkg/aic8800`、JELOS joypad 驱动），已 `.gitignore` 排除，
  请按各自上游的许可证获取。
- Rockchip 的 `idbloader/uboot/trust` blob 与 EmuELEC/ArkOS 的镜像同样不分发。
- 用到的上游：torvalds/linux 6.12.y、Rocknix 的 RK3326 补丁层、radxa-pkg/aic8800 驱动、
  Mesa（panfrost）。
