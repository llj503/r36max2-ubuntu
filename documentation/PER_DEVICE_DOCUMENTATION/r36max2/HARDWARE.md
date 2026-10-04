# 硬件画像（省掉你插逻辑分析仪的时间）

[← 返回 README](../../../README.md)

- SoC RK3326 / PX30，4x A35，Mali-G31 MC1（Bifrost v7，panfrost 支持 GLES 3.1）。
- 屏：DSI，`panel-generic-dsi` + `panel_description`，实际是 ST7703 系克隆屏，原生 1024x768。
- PMIC rk805/rk817（`vdd_logic` 会被别的消费者顶在 975 mV —— 见 [GPU.md](GPU.md)）。
- WiFi/BT：**AIC8800DC 是 USB 设备**（`a69c:88dc`，挂在 `ff300000` 的 dwc2 上），不是 SDIO。
  `chip_sub_id == 2` 属于 h_u02 版，需要 `fmacfw_patch_8800dc_h_u02.bin` 那一套固件。
- USB 拓扑：只有 dwc2 一个控制器且被 WiFi 占用 → **没有外置 host 口**，Type-C 插键盘没戏（试过）。
- 无 UART 焊盘、无调试串口 —— 所有远程观测靠 FAT 分区日志 + 屏幕状态页 + `/dev/fb0` 截图，手法见 [DEBUGGING.md](DEBUGGING.md)。
- 1 GB RAM；TF 卡分两个区：FAT `BOOT`（u-boot 读这里）+ ext4 根。
