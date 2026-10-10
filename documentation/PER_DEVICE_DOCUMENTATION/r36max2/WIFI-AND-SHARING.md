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
3. **加密**：看走的是哪条通道 —— 见下面两节。`wifi.txt` 走 `wpa_passphrase`，产出的是
   WPA2-PSK 的 PBKDF2 哈希，**纯 WPA3-个人 连不上**（要设 WPA2 或混合模式）；ES 菜单那条
   通道写的是 `key_mgmt=WPA-PSK SAE`，混合与纯 WPA3 都能连。

## 在 ES 里配网（不用把卡插回电脑）

设置菜单里多一条 **Wi-Fi 网络**：打开就扫（"正在查询Wi-Fi网络"），列表里每个热点可以用摇杆选，
选中后给 `网络选项：` —— 已存过的显示 **已保存**、当前连着的显示 **已连接**，可以
**连接** 或 **忘记**；没见过的网络会让你用**屏幕键盘**输入密钥（这个 fork 自带的
`GuiTextEditPopupKeyboard`，`UseOSK` 在非 x86 构建里默认就是 true，不需要外接键盘）；
列表里还有 **手动输入**，用于隐藏的 SSID。

页面顶部现在有一条 **IP地址**：连上了就是那个地址，没连上显示 **未连接**（`0105` 补丁）。
这条不是顺手加的装饰 —— `0103` 为了让菜单出现，打开的是 `GuiWifi` 而**不是**
fork 自己的 `openNetworkSettings()`（后者一页里还顺手开关 sshd、samba、simple-http、
syncthing、rclone、wireguard，这台机器上一个都没有），而**整棵树唯一的一条 IP 行就长在
`openNetworkSettings()` 上**。所以那时 ES 对"连上了"的全部回答只有那句
**连接成功** —— 偏偏 `wifictl` 是**故意**把"关联成功"当成功、把"拿到地址"当环境问题的
（口令错永远关联不上，那才是要报的失败；DHCP 慢或不发地址不该报"连接失败"这种谎）。
两边凑一起，"连上了但没有地址"这个情况以前**没有任何地方能看见**。
地址多于一个时和设置页一样变成 `x.x.x.x (+)`，点开列出全部；这一支的
`AVAILABLE IP ADDRESSES:` 上游本来就没译成中文，这里保持一致没有另加翻译。

这条菜单不是我们写的前端，是 fork 里本来就有的 `es-app/src/guis/GuiWifi.cpp`，它整个后端只有
一个外部程序：**`/usr/bin/wifictl`**（`packages/wifi-setup/wifictl`）。这个路径不是风格问题 ——
`ApiSystem::isScriptingSupported(WIFI)` 查的就是这个字面路径，文件不在，菜单项根本不出现，
也不会报错。所以：

| 菜单里做的事 | 实际执行的 |
| --- | --- |
| 打开页面 / REFRESH | `wifictl scanlist`（`wpa_cli scan` + 读 `scan_results`） |
| 忘记之后刷新列表 | `wifictl list`（读缓存，不再扫） |
| 看已存网络 | `wifictl list_saved`（解析 wpa_supplicant 的 conf） |
| 连一个新网络 | `wifictl enable` → `wifictl connect "<ssid>" "<psk>" "<country>"` |
| 连一个已存的 | `wifictl connect_saved "<ssid>"` |
| 忘记 | `wifictl forget_saved "<ssid>"` |

两条 ES 侧的约定是**读代码**读出来的，不是猜的：`executeScript()` 就是 `system(cmd) == 0`，
所以失败必须**非零退出**（否则界面会告诉你连上了）；`executeEnumerationScript()` 把每一行 stdout
变成一行菜单（`strtok(line, "\n")`），所以打印空行就等于多出一个可点的空白网络。

和 `wifi.txt` 的关系（同一个文件，两种语义，这条最容易踩）：

* 两边写的都是 `/etc/wpa_supplicant/wpa_supplicant-wlan0.conf`，因为
  `r36-wpa@wlan0.service` 只读这一个路径。在菜单里加的网络重启后还在。
* `wifi.txt` 是**声明式**的：它一旦被改动，`r36-wifi-setup` 会把整个文件重写成一个网络。
  也就是说**你在菜单里加的东西会被它清掉**。反过来，菜单永远只增删自己那一条。
* 存法不一样：`wifi.txt` 只存哈希（明文不进 rootfs），菜单存的是引号里的口令。原因是
  SAE 的握手用的是口令本身，预哈希的 PSK 做不了 WPA3 —— 这条 conf 权限 600、只有 root 能读，
  而且**从不往 FAT 上写**。
* 菜单写的 AKM 是 `key_mgmt=WPA-PSK SAE`（`proto=WPA RSN`、`ieee80211w=1`），探测里
  wpa_supplicant 报回 `key_mgmt: 0x402` = WPA-PSK|SAE，WPA2 和 WPA3-个人都能连。
  **不要写 `WPA2-PSK`**：那是 hostapd 的词，wpa_supplicant 会报
  `Line 8: invalid key_mgmt 'WPA2-PSK'`，而它一旦解析失败是**整个文件**都不读
  （`Failed to read or parse configuration` → 进程 255 退出），
  连带把本来能用的那个网络一起打死。第一次在卡上试这个脚本就撞上了这件事，断了两分钟。
  现在 `publish_tmp()` 装任何东西之前先用一个不存在的网卡跑一遍 `wpa_supplicant -dd -O`
  当校验器（`-O` 保证它不碰真的控制接口），解析不过就拒绝安装、保持原文件不动。

## 实测状态（2026-10-10）

卡上没有重刷，是把新 ES 二进制 + `zh_CN` catalog + `/usr/bin/wifictl` 直接部署上去，然后
**按 ES 的调用方式**逐个跑 `wifictl`：

| 调用 | 结果 |
| --- | --- |
| `wifictl scanlist` | 2 秒、5 行、**0 个空行**（隐藏 SSID 被跳过；空行在 ES 里会变成一条能点开的空白网络） |
| `wifictl list` / `list_saved` | 一个给可见网络，一个给 conf 里存的 SSID |
| `wifictl has_ap_mode` | **rc=1** —— 退 0 会让 ES 加上 LOCAL PLAY MODE / ad-hoc 两个开关，这版镜像没有实现那个功能 |
| `wifictl enable` | rc=0，supplicant 保持 active |
| `connect <在用的 SSID> <口令> CN` | **rc=0，用时 1 秒**，`wpa_state=COMPLETED`、`key_mgmt=SAE` —— 这张 AIC8800DC 实际跑起了 WPA3-个人（热点是 WPA2-PSK+SAE 混合） |
| `connect <不存在的 SSID> …` | **rc=1**，报 `still on "…"(COMPLETED) after 40s, not on "…"`；在用网络没掉，IP 不变 |
| `connect <在范围内、但口令错的 SSID>` | **第一版把整台机器弄下线了** —— 见下面"两次真实的失败"。这一行也是为什么上表那句"在用网络全程没掉"只对了一半：不在范围内的 SSID 会被 wpa 立刻放弃，在范围内的会一直重试 |
| `forget_saved <那条>` | rc=0，conf 从 2 个块变 1 个，只删该删的，链路保持 UP。（第一版在这里重启了服务，实测会让卡"看起来掉线"几秒 —— 改成 `remove_network` + 只重写文件，不重启） |
| `connect_saved <在用 SSID>` | rc=0、1 秒，`key_mgmt=WPA2-PSK`：选中的是 `wifi.txt` 那条**哈希形式**的块，它做不了 SAE，正好把两条通道的存储差别量出来了 |
| `connect_saved <没存过的>` | rc=1，`"…" is not saved`，不挂起 |
| 服务里裸 `wifictl` 找不找得到 | `systemd-run` 实测 `PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin` → `/usr/bin/wifictl` ✅（ES 的 enumeration 就是这么调的） |

整套测试跑完，`/etc/wpa_supplicant/wpa_supplicant-wlan0.conf` 与测试前 `cmp` **逐字节相同**。

**"设置 → Wi-Fi 网络"这一行已经在屏幕上确认**（2026-10-10；卡上跑的是 `7d5cc138` +
现场部署的 `92272ebc` ES 二进制）。代码侧的兜底是 `post_patch()` 里的 grep：
0103/0104/0105 任一条没打上就 `die`，构建过不去。

**上面那条 IP地址 行还没在屏幕上看过**（写下本文时卡不在电脑上、局域网里也没有这台机器）。
它现在的证据只到这三条：`0101..0105` 在一个干净解包上按文件名顺序逐个 `patch -p1` 且**每条都查
了退出码**（`scripts/unpack` 自己不查，见下面那节）；改过的 `GuiWifi.cpp` 用这个 target 自己的
`CXX_DEFINES/CXX_INCLUDES/CXX_FLAGS` 跑 `-fsyntax-only` 过，**未打补丁的对照文件也过** —— 否则
"编译通过"这件事跟补丁没关系；产物里 `ca9daf6b` 与 `install_pkg` 逐字节相同，`zh_CN` catalog 里
`IP地址`、`未连接` 两个串都在。**屏幕上那一行到底长什么样、连上之后填的是不是真地址，还没量。**

顺便量清一件会影响你日后排查的事：**别指望在 ES 日志里看到"菜单被打开了"。** 这个构建的
`es_log.txt` 只写 WARNING 和 ERROR（当场统计：115 WARNING、13 ERROR、**0 条 INFO**），而
`executeScript()` 里那句 `LOG(LogInfo) << "Running wifictl …"` 是 INFO 级，根本不落盘。
要在设备上判断"连过没有"，看副作用：连过一次之后 `/root/.emulationstation/batocera.conf`
里会出现 `wifi.ssid=…`（`saveSystemConf()` 写的），并且 conf 里那条块会从哈希形式变成
`psk="…"` + `key_mgmt=WPA-PSK SAE` 形式。两边都没有 = 只打开过页面、没连过。

（同一时间日志里出现 14 次 `Unknown help icon "上/下"!`，就在翻菜单那几分钟，之前那份日志
是 0 次。**没有归因**：看着像中文界面下某个帮助提示在主题里找不到图标，属显示层噪声。）

## 第一次上机就撞出来的事故（用户实测，不是我测出来的）

屏幕上走完"选 `aqk` → 屏幕键盘输密码"之后，**卡从局域网上彻底消失**，而且用户在设备上
"连接回原来那个网络"也失败。把卡插回电脑、离线挂载读现场，journal 给了完整因果：

```
14:14:36  CTRL-EVENT-SSID-TEMP-DISABLED id=1 ssid="aqk" auth_failures=3 duration=30 reason=CONN_FAILED
14:14:49  CTRL-EVENT-SSID-REENABLED id=0 ssid="360JDCWiFi-E378"
14:14:49  wlan0: Association request to the driver failed        <- 好用的这个也连不上
14:15:32  wlan0: Association request to the driver failed
```

ES 侧对上的是这两行：

```
14:14:46  Error executing wifictl connect_saved 'aqk'
14:15:30  Error executing wifictl connect_saved '360JDCWiFi-E378'
```

两件事叠在一起，第二件才是致命的：

1. **口令错但在范围内的网络会把选择卡住**：wpa_supplicant 一直重试它，不自动退回能用的那个；
   我第一版只等"关联成功"，于是"连接失败"实质等于"没网"。（不在范围内的 SSID 会被立刻放弃，
   所以我自己那轮测试看不到这个问题 —— 这就是"你的证明在修复不存在时长得一模一样"。）
2. **反复重启 supplicant 会把 AIC8800DC 弄死**：12 分钟里 4 次 `systemctl restart
   r36-wpa@wlan0`（每次还配一句 `iw reg set`，它会重启信道），之后驱动对**任何**关联请求都回
   `Association request to the driver failed` —— 连一整天都好的那个网络也一样。所以只能断电重插。

三个改动，都在 `wifictl` 里：写完 conf 用 `wpa_cli reload_config` 让常驻进程重读文件，
**不重启服务**（`reload_config` 会按文件重建运行时网络，id 和块仍然对得上 —— 当初"要重启"的
理由不成立）；失败就把改动前的快照写回去 + `reload_config`，"连接失败"从此意味着"回到你原来
的网络"；只在国家码真的变化时才 `iw reg set`，并用 `select_network` 明确去连用户点的那个 SSID。

现场处理是离线做的：口令错的那条 `aqk` 块从 conf 里删掉（2 块→1 块，剩下的是原来那条哈希块），
再把修好的 `wifictl` 装上去；原 conf 备份在构建机 `/root/card-conf.before-aqk-removal`。

**还有一件要记住的事：ES 的 ERROR 行会带整条命令，里面是明文口令。** 上面 `executeScript()`
那句 INFO 不落盘，但失败时的 `LOG(LogError) << "Error executing " << command` 会，实测卡上
`/root/.emulationstation/es_log.txt` 里就有 2 行连着 SSID 和口令。文件是 root 0600 目录下的，
和 FAT 上明文的 `wifi.txt`、菜单写进 conf 的 `psk="…"` 是同一档暴露，没有更大口子 —— 但排查时
别把这份日志贴到公开场合。（我没改用户的日志文件，只做了计数。）




