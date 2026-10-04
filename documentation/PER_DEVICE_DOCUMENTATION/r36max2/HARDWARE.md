# 硬件画像（省掉你插逻辑分析仪的时间）

[← 返回 README](../../../README.md)

- SoC RK3326 / PX30，4x A35，Mali-G31 MC1（Bifrost v7，panfrost 支持 GLES 3.1）。
- 屏：DSI，`panel-generic-dsi` + `panel_description`，实际是 ST7703 系克隆屏，原生 1024x768。
- PMIC rk805/rk817（`vdd_logic` 会被别的消费者顶在 975 mV —— 见 [GPU.md](GPU.md)）。
- WiFi/BT：**AIC8800DC 是 USB 设备**（`a69c:88dc`，挂在 `ff300000` 的 dwc2 上），不是 SDIO。
  `chip_sub_id == 2` 属于 h_u02 版，需要 `fmacfw_patch_8800dc_h_u02.bin` 那一套固件。
- **这块板子只能用 2.4GHz**：驱动只实例化 2.4G 信道（`rwnx_get_countrycode_channels support
  channel:1 2 … 14`、`lvl_11b_11ag_5m5_2g4`），`iw reg get` 里那些 5G 频段是 world domain 的
  通用表、PASSIVE-SCAN，用不上。**路由器只开 5G 时掌机一定连不上**，别把它当成配网 bug。
  配网脚本用 `wpa_passphrase` 生成的是 `key_mgmt=WPA-PSK`（WPA2），所以 **WPA3-only 的网络也不行**
  —— 设成 WPA2-PSK(AES) 或 WPA2/WPA3 混合。
- USB 拓扑：只有 dwc2 一个控制器且被 WiFi 占用 → **没有外置 host 口**，Type-C 插键盘没戏（试过）。
- 无 UART 焊盘、无调试串口 —— 所有远程观测靠 FAT 分区日志 + 屏幕状态页 + `/dev/fb0` 截图，手法见 [DEBUGGING.md](DEBUGGING.md)。
- 1 GB RAM；TF 卡分两个区：FAT `BOOT`（u-boot 读这里）+ ext4 根。
