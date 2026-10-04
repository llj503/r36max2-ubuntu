# 换网络 / 交给别人用（这块板子没有键盘也没有串口）

[← 返回 README](../../../README.md)

镜像里可以完全不带任何凭据：`R36_BAKE_WIFI=0 bash scripts/build-rootfs.sh`。
使用者只需要在 Windows 上往 BOOT(FAT) 分区放一个两行的文本文件：

```
wifi.txt:
    SSID=我的WiFi名
    PSK=我的密码
    COUNTRY=CN        # 可选
```

`r36-wifi-setup.service` + `.timer`（开机 30 秒后、之后每分钟）发现文件内容变了，就用
`wpa_passphrase` 生成 `/etc/wpa_supplicant/wpa_supplicant-wlan0.conf`（**只存 PBKDF2 哈希**，
明文那行 `#psk=` 会被剥掉，权限 600），`iw reg set`、重启 `r36-wpa@wlan0`，等关联 + DHCP，
然后把结果写回 **`BOOT:\wifi-status.txt`**：

```
OK: connected to my-wifi, IPv4=192.168.31.57  (ssh root@192.168.31.57)
```

连不上的话这个文件会附上附近扫到的热点清单，所以在电脑上就能判断是密码错还是名字错，
不用拍屏幕。改完文件不用重刷也不用重启。

**注意 wifi.txt 是明文躺在 FAT 分区上的**（FAT 没有权限位）—— 公共场合或借给别人用之后，
删掉它；设备侧的配置文件里只有哈希。这个取舍和 Raspberry Pi OS 的 `network.txt` 一样，
是"没有任何输入通道"的板子唯一现实的做法。

## 连不上时先看这三条

1. **`wifi-status.txt` 到底有没有生成**。没生成 ≠ 连不上，而是**脚本根本没读到 `wifi.txt`**。
   `BOOT:\r36-boot.txt` 里如果有
   `mmcblk1p1: Can't mount, would change RO state`，就是这个原因：`r36-status-screen` 每 30 秒
   把 BOOT 以 `ro` 挂到 `/mnt/boot`，而 `r36-wifi-setup.timer` 的 `OnBootSec=30` 让它同一时刻
   去用 `rw` 挂**同一个块设备的另一个挂载点** —— 内核不允许同一设备以不同 RO 状态二次挂载，
   脚本 `exit 0`，而且它在写状态文件之前就退出了，所以你在电脑上什么都看不到。
   v20 的卡实测踩过（2026-10-04，日志时间 `10:11:32`，uptime 对得上 30 秒边界）。
   修法：四个消费者（`r36-bootlog` / `r36-status-screen` / `r36-fwswap` / `r36-wifi-setup`）
   统一用 `/mnt/boot` 这一个挂载点，已经挂上就复用、只卸载自己挂的那次。
2. **频段**：这块板子只有 2.4GHz（见 [HARDWARE.md](HARDWARE.md)），5G 专用的 SSID 一定连不上。
3. **加密**：`wpa_passphrase` 产出的是 WPA2-PSK，纯 WPA3-个人 的网络连不上，设 WPA2 或混合模式。

