# 已知问题与未做

[← 返回 README](../../../README.md)

- ~~**（v21，未定位）AIC8800DC 在枚举后约 32.6 s 从 USB 总线上消失**~~ **已定位并修好：掉的是
  `vbus_host` 那一路电，不是驱动、不是省电。**
  原现象：`usb 1-1: USB disconnect, device number 2`，掉线前 dmesg 完全静默，
  九次开机对齐到枚举时刻是 32.601…32.614 s。
  定案的证据链来自 v21 出厂镜像的一整场开机（`BOOT:\r36-timeline.txt`，tick 每 3 s）：
  `33.762865 s` `vbus_host: disabling` → `41.229879 s`
  `aicwf_usb_bus_txmsg: Txmsg wait timed out` → `45.283053 s`
  `cmd_mgr_queue cmd timed-out ... 117-MM_GET_STA_INFO_REQ`，此后 `rwnx_cmds.c` 把命令队列
  锁进 `RWNX_CMD_MGR_STATE_CRASHED`，一直到 664 s 还在刷 `cmd queue crashed`。这一场里 USB
  设备没掉、`networkd` 的地址也还在（`192.168.0.141/24`），所以症状是"连着但什么都不通"。
  `vbus_host` 是 `&u2phy` 的 `otg-port` 的 `ext-supply`：otg-port 在 33.7 s 放掉引用，
  稳压器就把模块的电撤了。给这个节点补 `regulator-always-on` 之后同一条时间线里
  `vbus_host: disabling`、`Txmsg wait timed out`、`cmd queue crashed`、`USB disconnect`
  四条全为零，uptime 373 s 时 ping 通、SSH 进得去、板子上 `curl https://api.github.com`
  返回 `HTTP/2 200`，`iw` 报 `signal -20 dBm`。
  当初排除过的方向都留在这里，因为它们**确实**都被实测过（每条一次独立开机取数）：
  芯片电源 `vbus_wifi`（全程 `use>=1`，单独加 always-on 无效——真正被撤的是另一路
  `vbus_host`）、dwc2/EHCI runtime PM（掉线前 hcd 与子设备都是 `active`）、驱动
  （黑名单后整场没有 `wlan0`，仍在同一时刻掉）、固件版本（4.0 与 5.0 都掉，4.0 还连不上）、
  关联与流量（不关联也掉）、蓝牙（`blacklist btusb` 后照样掉）、芯片省电
  （`ps_on=0 dpsm=0` 无效；修好之后 `ps_on=Y` 也照样稳定，所以省电不是原因）、
  OTG 模拟开关 `gpio0_A7`（钉在 bootloader 电平，无效）、第二组 EHCI/OHCI 口（保持 disabled）。
  两条教训写在这里：**掉线时"地址还在"不等于链路可用**，判据得是能不能真的收发；
  以及 `regulator_summary` 里名字相近的两路 `vbus_wifi` / `vbus_host` 要分开看，
  当时只盯住前者，白跑了七八场开机。
- ~~**（v21 实测）镜像里的 EmulationStation 缺内嵌资源，没主题时屏幕基本是空的**~~
  **已修：`resources/` 那棵树必须跟二进制一起装，它不是主题。**
  SSH 里直接跑 `emulationstation`（`/root/.emulationstation/themes` 为空）：进程不退出
  （20 s 与 150 s 两次都活着），但 3438 行日志里 3429 行是
  `Could not find appropriate font face for character N for font :/ubuntu_condensed.ttf`，
  另有 `:/help/button_a.svg missing`。`:/...` 不是编译进二进制的 Qt 资源（源码树里
  根本没有 `.qrc`，`strings` 也搜不到字体内部名），`ResourceManager` 是按
  `~/.emulationstation/resources`、数据目录、**可执行文件同目录**、cwd 这个顺序去找
  真实文件的。把源码里那 14 MB / 145 文件的 `resources/` 拷到板子的
  `/usr/local/bin/resources` 再跑一次：日志从 3438 行掉到 **5 行，字体与帮助图标错误
  都是 0**。剩下的 `No systems found!`（卡上没有 ROM）和 `serial_number_check not found`
  是另一回事。
  **注意 `/dev/fb0` 抓不到 ES 的画面**：ES 走 DRM plane 出图，fbdev 那份只有控制台
  （实测抓到的是 `r36-status-screen` 的文字），要看 ES 只能拍照。
- **（v21 实测）状态页的 `batt: ?%`，但内核是知道电量的**：`/sys/class/power_supply/rk817-battery`
  在，`cap=99 status=Discharging`，`voltage_now` 为空。`r36-status-screen` 大概读的是
  `voltage_now` 或者别的供电路径，需要跟着 `capacity` 改。
- **睡眠能进不能出**：`echo mem` 进得去，电源键和 RTC 闹钟都叫不醒（只能长按强制断电）。
  `wakeup-source` 和 pwrkey 的 `power/wakeup` 都是好的，怀疑主线 `rk8xx` 没把 PMIC 中断注册成
  wakeirq，而厂商 BSP 依赖私有的 `rockchip,sleep-mode-config` + `rk817_slppin_*` 引脚复用。
  目前 `suspend/hibernate/sleep.target` 全 mask，电源键 `HandlePowerKey=ignore`
  （装了 udev 之后 logind 会开始抓 KEY_POWER，默认是 poweroff，实测短按就关机）。
  **测睡眠前一定先设 RTC 闹钟**，否则就是把设备关进小黑屋。
- 蓝牙 `hci0: command 0x2048/0x204b tx timeout`：AIC 的 BT 固件没配好。注意
  **`blacklist btusb` 不能修上面那条 32.6 s 掉线**（v21 实测：黑名单生效后
  `/sys/class/bluetooth` 为空、`/sys/bus/usb/drivers/btusb` 目录为空，芯片仍在同一
  时刻掉），但镜像里没有 bluez（`/usr/lib/bluetooth`、`bluetoothd` 都不存在），
  所以这颗模块的 BT 功能本来就不可用；要不要继续 blacklist 只影响 `hci0` 是否出现。
- ~~按键目前只有 input 事件，没有用户空间映射~~ **已解决**：`r36-keymapper`（uinput 键鼠桥）
  已进 v20，掌机按键可以当键盘/鼠标用；但注意它和 EmulationStation 抢同一个设备，
  见 [EMULATIONSTATION.md](EMULATIONSTATION.md) 的"摇杆键鼠桥和 ES 抢同一个设备"。
- **EmulationStation 这一整套目前只存在于那张 64 GB 卡 + `scripts/`、`tools/` 脚本里，没进镜像**：
  包括 `/root/es` 编译产物、`es_input.cfg`（含新加的 `joystick1left/up` 轴绑定）、
  `~/.emulationstation/themes/art-book-next`、`es_settings.cfg` 的 `ThemeSet`、
  `/usr/local/bin/r36-es` 和 `r36-osk` 的键名别名修正。要交给别人用得再出一版镜像（v21），
  把上面这些折进 `scripts/apply-*.sh` 的流程 —— **别只改卡上，重刷就丢**。
- **v20 镜像里 `wifi.txt` 这条通道是死的**（2026-10-04 实测定案）：`/usr/local/sbin/r36-wifi-setup`
  在（4846 B，10-02 18:13），但 **`r36-wifi-setup.service`/`.timer` 从未装进
  `/etc/systemd/system/`**，两个 `*.wants/` 软链里也没有它 —— 没有任何东西去运行它，所以两轮开机
  `BOOT:\wifi-status.txt` 一个字节都没生成。当时还误判过两次：一次怪 `WPA3-SAE`（后来你把 2.4G
  改成 WPA2 了），一次怪 `r36-status-screen` 的只读挂载与它冲突（那句 `Can't mount, would change
  RO state` 确实存在、也确实修了，但它不是这次的堵点）。出镜像那会儿用的 `apply-v19.sh` 还没带
  第 91 行那句 cp，所以是**历史镜像**的问题：现在的 `scripts/apply-v19.sh` 会装这两个单元，
  v21 构建完请在卡上确认 `systemctl is-enabled r36-wifi-setup.timer` 是 `enabled`。
  这张卡已由 usbipd 直通 WSL 手工补装并顺带把烧死的旧网络 `Xiaomi_4FD3` 换成 `360JDCWiFi-E378`
  （`psk` 写的是 PBKDF2 哈希，0600），原件在卡上 `/root/r36-backup-20261004/`。
- **ES 还没有真 ROM**：现在跑的 `demo` 系统是假的（"启动"= 写一个标记文件），用来验证
  列表→启动→回列表的回路。真 ROM 在另一张 128 GB 卡上，而那张卡是**绝对不碰**的
  （上面有能用的 ArkOS + ROMS），所以要么由他把 ROM 拷到 64 GB 卡的根分区（还有 ~51 GB 空闲），
  要么另想办法；这一步需要他参与决定拷哪些。
- ~~左摇杆导航还没被眼睛确认~~ **已确认（2026-10-04）**：`joystick1left/up` 是照
  `InputConfig.cpp` 的判定写进去的，目视结果推摇杆能移动光标、能切条目、**方向正确**
  （在 `r36-es --kmsdrm` 下测，weston 全程没启动）。原始轴事件满行程（`ABS_X/Y/RX/RY` ±1800）
  早先也实测过。唯一还没逐个方向核对的是厂商 dtb 里的 `invert-absx/absry` 标志 —— 既然实测
  方向就是对的，这条只剩文档层面的意义；真出现反向就改
  `packages/rk3326/es-launcher/es-input-*.cfg` 里那两条绑定的 `value` 正负
  （当时的 `scripts/k72-es-sticknav.sh flip` 已删）。
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
