# 刷写与首启

[← 返回 README](../../../README.md)

```bash
# 镜像本体不入库（.gitignore 排除了 distributions/*.img.xz，里面含 AIC 厂商固件 blob），
# 所以下面这个路径是你自己构建出来的产物，或你本地留存的那一份；仓库里只有它的 sha256。
# 只刷 64 GB 那张卡；插回电脑后先确认设备号，别写错盘
xzcat target/r36max2-ubuntu-v21.img.xz | sudo dd of=/dev/sdX bs=8M status=progress oflag=sync
# 写前先对一遍校验和（distributions/ 里存着每一版的记录）
sha256sum -c target/r36max2-ubuntu-v21.img.xz.sha256
```

开机约 40 秒后 tty1 会出现状态页（IP、信号、失败单元、电量）。想关掉就在 BOOT 分区建空文件
`noscreen`。卡上的其它开关（建空文件即生效，删掉恢复）：

| 文件 | 作用 |
| --- | --- |
| `rescue` | 以 `rescue.target` 启动 |
| `usbhost` | 换 `rk3326-xifan-r36max2-usbhost.dtb`，打开第二组 USB 主机控制器 |
| `use-boot-fw` | 用 BOOT 分区 `fw/aic8800DC/` 里的固件替代系统内的，并重载 WiFi 驱动 |
| `r36-log` | 立刻再写一份状态报告到 `r36-boot.txt` |
