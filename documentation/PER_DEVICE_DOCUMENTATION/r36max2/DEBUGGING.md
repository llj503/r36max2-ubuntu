# 没有串口怎么调试（这套方法比插 UART 更有用）

[← 返回 README](../../../README.md)

1. **FAT 分区当日志盘**：`r36-bootlog.timer` 每 2 分钟把 `ip`/`iw`/`rfkill`/`wpa_cli`/
   `systemctl --failed`/USB 拓扑/`/dev/input/by-path`/声卡/drm/devfreq/`dmesg`/
   `journalctl -b -p 4` 写进 `BOOT:\r36-boot.txt`。卡插回 Windows 就能读，一份报告能把
   整条因果链钉死。
2. **u-boot 启动失败会自己往 FAT 写 `error.log`** —— 引导层的免费证据（我就靠它发现
   `boot.ini` 里用 `${变量}` 当文件名会导致 `dtb load fail` 黑屏）。
3. **屏幕可以远程"看"**：`ssh root@dev "head -c N /dev/fb0"` → `raw2png.py`（纯 stdlib 的
   PNG writer）。这块屏 `virtual_size=1024,1536` 但可见只有 768 行、`bpp=32`、
   **没有 `line_length` 属性**（自己算 `W*4`）、字节序小端 BGRX。
4. `by-path`/`by-id` 目录空 = udevd 没跑；`ip a` 只有 lo = 驱动层问题；有 wlan0 无 IP =
   supplicant/DHCP 层。这个区分帮我找到了"rootfs 里没装 `udev` 包"这个真正的拦路虎
   （Ubuntu 24.04 起 `udevd` 从 `systemd` 拆出去了）。
