# 已知问题与未做

[← 返回 README](../../../README.md)

- **睡眠能进不能出**：`echo mem` 进得去，电源键和 RTC 闹钟都叫不醒（只能长按强制断电）。
  `wakeup-source` 和 pwrkey 的 `power/wakeup` 都是好的，怀疑主线 `rk8xx` 没把 PMIC 中断注册成
  wakeirq，而厂商 BSP 依赖私有的 `rockchip,sleep-mode-config` + `rk817_slppin_*` 引脚复用。
  目前 `suspend/hibernate/sleep.target` 全 mask，电源键 `HandlePowerKey=ignore`
  （装了 udev 之后 logind 会开始抓 KEY_POWER，默认是 poweroff，实测短按就关机）。
  **测睡眠前一定先设 RTC 闹钟**，否则就是把设备关进小黑屋。
- 蓝牙 `hci0: command 0x204b tx timeout`：AIC 的 BT 固件没配好，必要时 blacklist `btusb`。
- ~~按键目前只有 input 事件，没有用户空间映射~~ **已解决**：`r36-keymapper`（uinput 键鼠桥）
  已进 v20，掌机按键可以当键盘/鼠标用；但注意它和 EmulationStation 抢同一个设备，
  见 [EMULATIONSTATION.md](EMULATIONSTATION.md) 的"摇杆键鼠桥和 ES 抢同一个设备"。
- **EmulationStation 这一整套目前只存在于那张 64 GB 卡 + `scripts/`、`tools/` 脚本里，没进镜像**：
  包括 `/root/es` 编译产物、`es_input.cfg`（含新加的 `joystick1left/up` 轴绑定）、
  `~/.emulationstation/themes/art-book-next`、`es_settings.cfg` 的 `ThemeSet`、
  `/usr/local/bin/r36-es` 和 `r36-osk` 的键名别名修正。要交给别人用得再出一版镜像（v21），
  把上面这些折进 `scripts/apply-*.sh` 的流程 —— **别只改卡上，重刷就丢**。
- **ES 还没有真 ROM**：现在跑的 `demo` 系统是假的（"启动"= 写一个标记文件），用来验证
  列表→启动→回列表的回路。真 ROM 在另一张 128 GB 卡上，而那张卡是**绝对不碰**的
  （上面有能用的 ArkOS + ROMS），所以要么由他把 ROM 拷到 64 GB 卡的根分区（还有 ~51 GB 空闲），
  要么另想办法；这一步需要他参与决定拷哪些。
- **左摇杆导航还没被眼睛确认**：`joystick1left/up` 绑定是照 `InputConfig.cpp` 的判定写进去的，
  原始轴事件也确认过满行程（`ABS_X/Y/RX/RY` ±1800），但"推摇杆光标到底动没动、方向对不对"
  只有看屏幕才知道 —— 反了就用 `scripts/k72-es-sticknav.sh flip`。
- **weston 的 vblank 丢失又出现了，但形态不同**：2026-10-03 20:49:17 起再次打出
  `[CRTC:39:crtc-0] vblank wait timed out`（`WARNING drivers/gpu/drm/drm_atomic_helper.c:1921`），
  到 21:31 还在间歇增加；**但这一轮 weston 侧 0 条 `Device or resource busy`、画面全程可以操作**。
  前两次是"每帧 EBUSY、只能重启"，所以"丢 vblank 一定立刻永久卡死 CRTC"要降级成
  "至少存在一种可继续的形态"，这条线（任务 #19）还没查到底。
- `r36-keymapper` 不处理 SIGTERM：每次 `systemctl stop` 都要等超时被 SIGKILL，unit 显示
  `failed`（其实是停成功了），并且白等几秒。
- **摇杆还差的两件小事**：轴方向只验证了"满行程能打到 ±1800"，没逐方向核对
  `invert-absx/absry` 这几个厂商调过的标志，也没验证单 ADC 电压梯的**组合键**
  （比如同时按两个键产生的中间电压档）；6.12.79 那条线目前跑的还是镜像里自带的整数
  GPIO 版模块，gpiod 版虽然同样能编（同一份源码），但没在 6.12 上重装验证过——
  注意它和新 dtb 的极性是配套的，别只换一半。
- 1 GB RAM：没上 zram/swap，编译大项目要省着点。
