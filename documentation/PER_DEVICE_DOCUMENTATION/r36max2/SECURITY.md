# 风险提示

[← 返回 README](../../../README.md)

所有实验都在 TF 卡上进行，eMMC 全程未写入 —— 拔掉卡就是原来的 EmuELEC。但改引导扇区、
刷错盘（我有两块卡，另一块是装着 ROM 的 128 GB）都会造成真实损失，动手前请先核对设备号。

**镜像的账号是 `ubuntu` / 密码 `ubuntu`（root 同密码）**，`tools/*/diagnostics/dev-*.sh` 这些调试脚本里也
直接写着 `sshpass -p ubuntu`。这是调试期的权宜做法：刷机后第一件事请 `passwd` 改掉，并且
不要把改过的密码提交回来。`build/wifi-cred.txt`（WiFi SSID/口令）已在 `.gitignore` 里排除，
`build-rootfs.sh` 从它读取生成 `wpa_supplicant-wlan0.conf`（`chmod 600` 进镜像）。
