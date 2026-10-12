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
| `connect <范围内的另一个网络>` | 用户实测（10-12）：**口令对也连不上**，而且日志证明它**根本没尝试关联那个网络**——`4-way` 在四个 boot 里全 0，口令从未被测到。所以这一行以前写的"口令错"是错的归因，见"第三次"那一节 |
| `forget_saved <那条>` | rc=0，conf 从 2 个块变 1 个，只删该删的，链路保持 UP。（第一版在这里重启了服务，实测会让卡"看起来掉线"几秒 —— 改成 `remove_network` + 只重写文件，不重启） |
| `connect_saved <在用 SSID>` | rc=0、1 秒，`key_mgmt=WPA2-PSK`：选中的是 `wifi.txt` 那条**哈希形式**的块，它做不了 SAE，正好把两条通道的存储差别量出来了 |
| `connect_saved <没存过的>` | rc=1，`"…" is not saved`，不挂起 |
| 服务里裸 `wifictl` 找不找得到 | `systemd-run` 实测 `PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin` → `/usr/bin/wifictl` ✅（ES 的 enumeration 就是这么调的） |

整套测试跑完，`/etc/wpa_supplicant/wpa_supplicant-wlan0.conf` 与测试前 `cmp` **逐字节相同**。

**"设置 → Wi-Fi 网络"这一行已经在屏幕上确认**（2026-10-10；卡上跑的是 `7d5cc138` +
现场部署的 `92272ebc` ES 二进制）。代码侧的兜底是 `post_patch()` 里的 grep：
0103/0104/0105 任一条没打上就 `die`，构建过不去。

**那条 IP地址 行已经在屏幕上确认了**（2026-10-12 早上，用户实测：连上在用网络之后屏上显示的是
真实地址）。卡上的二进制是 10-10 离线放进去的 `ca9daf6b`，与 `install_pkg` 逐字节相同，原件备份在
`/root/emulationstation.pre-ip`。代码侧的证据链仍然是那三条：`0101..0105` 在干净解包上按文件名
顺序逐个 `patch -p1` 且**每条都查退出码**（`scripts/unpack` 自己不查）；改过的 `GuiWifi.cpp` 用这个
target 自己的 `CXX_DEFINES/CXX_INCLUDES/CXX_FLAGS` 跑 `-fsyntax-only` 过，**未打补丁的对照也过**
—— 否则"编译通过"跟补丁无关；产物里 `ca9daf6b` 与 `install_pkg` 逐字节相同。
**没量到的**是"连上之后那个地址会不会自己刷新"——它依赖 `load()` 被再次调用（REFRESH 或连接成功
那个框），这个我还没在屏上验证过第二个网络。

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
2. ~~**反复重启 supplicant 会把 AIC8800DC 弄死**~~ —— **这条当天就被推翻了，见下一节**。
   当时看到的是"12 分钟里 4 次重启之后驱动对任何关联请求都失败"，但那次没有对照组。

## 第二次的尸体自己开口了：不是重启弄死的，是我的回滚（2026-10-10 下午，离线读 journal）

按上面第 2 条改掉重启之后，用户在屏幕上又走了一次同样的流程，卡**又**下线了，而且这次更久。
把卡插回电脑离线读 `system.journal`，两本 boot 一对，前面那个归因直接倒下：

| boot | 时段 | `systemctl` 重启 supplicant | `Association request to the driver failed` | `CTRL-EVENT-CONNECTED` |
| --- | --- | --- | --- | --- |
| `-1` | 07:57–14:15（旧 wifictl，会重启） | 0 条被记到 | 16 | 11 |
| `0` | 14:37–16:08（**改完之后，重启 0 次**） | **0**（14:37:42 起，16:08:33 才停） | **34** | **1**（开机那次） |

boot 0 全程一次都没重启过服务，wedge 反而翻倍，而且**再也没有连上过**。所以"别重启"不是解药，
只是少了一种踩法。真正的时间线在 boot 0 里能逐秒对上，而且**矛头指向我自己加的"回滚"**：

```
14:42:03  ES: Error executing wifictl connect 'aqk' '<口令>' ''   <- 40 秒等待到点，脚本开始回滚
14:42:16  wlan0: CTRL-EVENT-ASSOC-REJECT bssid=00:00:00:00:00:00 status_code=1
14:42:16  kernel: rwnx_rx_sm_connect_ind ind->status_code:1 ... drv_conn_state:0
14:42:17  wlan0: Association request to the driver failed        <- 从这一秒起到 16:08，34 次
```

被拒的是**好网络那个 BSSID**（`c8:5b:a0:e7:e3:7a`），时刻正是回滚把 conf 写回去并 `reload_config`
之后 —— reload 让常驻进程去重新关联原来的网络，而**这一次"回来"的关联被驱动判死**，之后
驱动的 connect 状态机对任何请求都不再接受。换句话说：跳到另一个信道/BSSID（`aqk` 在 2462 MHz，
在用的是 2412）再回来，这个动作本身就够了，**不需要任何重启**。

三个改动，都在 `wifictl` 里（`3a672179`）：

* 回滚不再 `reload_config`，改成**先把刚加进去的那个运行时网络 `remove_network` 掉**、再把文件
  写回去。`remove_network` 是 `forget_saved` 一直在用的路子，那个实测过"链路保持 UP"；文件里
  最后追加的块删掉也不会让别的 id 位移。
* 回滚之后 25 秒仍然不是 `COMPLETED`，就**自动做一次驱动复位**：停 supplicant → `rmmod
  aic8800_fdrv` `aic_load_fw` → `modprobe` 回来 → 等 `wlan0` 出现 → 重连。这两个 `.ko` 是可加载
  的（`/lib/modules/7.2.9/extra/`，`/etc/modules-load.d/r36max2.conf` 里点名），`r36-fwswap` 已经在
  开机场景证明这套 rmmod/modprobe 在这块板子上走得通。**运行时唯一的新东西是常驻进程占着
  `wlan0`**，所以必须先 `systemctl stop`，否则 `rmmod` 只是返回"Module is in use"、复位悄悄变成空操作。
* 新增 `wifictl recover` 走同一段代码，给人手用 —— ES 不会调它（它只调那十个），但调试时不该
  为了触发复位先故意失败一次。

**上面这三条改动，第一条当天晚上就又被推翻了一半，见"第三次"那一节。** 留在这里是因为它记的是
"为什么不再重启服务"这个理由，那个理由仍然成立；不成立的是"回滚安全了"。

## 第三次：干净样本把"口令错"彻底删掉，顺手抓到我自己写的回滚（2026-10-12 早上）

用户把卡放回机器、开机、连上了在用网络（**屏幕上看到了真实 IP —— `0105` 那一行第一次在屏幕上
成立**），然后去连 `aqk`，并且明确说**口令是对的**。这是第一个"芯片从头就是好的"的样本，
结果它把两件事一次说清：

| boot | 时段 | 重启 supplicant | 驱动拒关联 | **握手(4-way)** | WRONG_KEY | 认证超时 | 连上次数 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| -2 | 10-10 07:57–14:15 | 0 条记录 | 16 | **0** | 0 | 0 | 11 |
| -1 | 10-10 14:37–16:08 | **0** | 34 | **0** | 0 | 0 | 1 |
| 0 | 10-12 07:53–08:10 | 0 | **0** | **0** | 0 | **2** | 1 |

`4-way` 那次是 `grep -ci` 数出来的（前一版我写成大写 `4-WAY`，那样连 "4-Way Handshake failed"
都匹配不到，0 是假的）。**四个 boot 全零 = 这台机器一次都没走到需要检验口令的那一步。**
所以"口令错"这个原因要从记录里删掉——它从来没被测试过，不是"测过并且通过"。

10-12 这个 boot 里 aqk 的真实经过，逐秒：

```
07:53:28  CTRL-EVENT-CONNECTED c8:5b… (360JDCWiFi-E378)        <- 好网络，屏上那个 IP 就是它
07:55:36  wifictl: still on "360JDCWiFi-E378" (COMPLETED) after 40s, not on "aqk"
07:55:36  wifictl: back on "360JDCWiFi-E378" (COMPLETED)        <- 我的回滚说：链路没事
07:55:37  Trying to associate with c8:5b…                       <- 回滚自己发起的重新关联
07:55:47  Authentication with c8:5b… timed out.
07:55:51  CTRL-EVENT-DISCONNECTED bssid=c8:5b… reason=3 locally_generated=1
07:55:52  CTRL-EVENT-SCAN-FAILED ret=-16   +  kernel: rwnx_cfg80211_scan is scanning, abort
          （一直刷到断电）
```

两件事同时定了：

1. **aqk 一条 `Trying to associate` 都没有。** 整个 boot 里那次关联只发生过好网络那个 BSSID，
   `aqk` 的 `f4:84:8d:b6:3c:a3`（10-10 那天出现过，2462 MHz）一次都没出现。常驻进程根本没去碰它
   —— 于是"连接失败"和口令没有因果关系。为什么没去碰，脚本当时没记录，这就是下面第 2 条改动要补的。
2. **是我的回滚把好好的链路拆了。** 它先说 "back on … (COMPLETED)"，一秒后自己发起重新关联，
   认证超时，链路掉光，然后驱动进入"`is scanning, abort`"——从此拒掉每一次扫描（`-EBUSY`），
   而这台机器唯一还能连网的路就是扫描。我 10-10 晚上加的"把每个网络都 enable 一遍再 reassociate"
   正是这一次多余关联的来源。

还测到一条我原本不抱希望的：**驱动复位这次真的执行了，而且不够。**

```
07:57:10  systemd-networkd: wlan0: Link DOWN                    <- 我的 ip link set down
07:57:11  kernel: aicwf_usb_exit … usb_deregister / aicwf_usb_disconnect   <- rmmod 不是空操作
07:57:12  Starting r36-wpa@wlan0…  → 07:57:23 Authentication timed out → 07:57:58 复位没救回来
```

`rmmod`/`modprobe` 确实跑了（不是"Module is in use"那种假成功），但这个 boot 里
`new high-speed USB device` **只出现过 1 次，就是开机那次** —— 也就是说驱动重新绑上的还是那颗
卡在"我正在扫描"里的芯片。**重载模块不等于复位芯片。**

所以 `wifictl` 现在是第四版（`/var/lib/r36-wifictl/audit.log` 会记下每一版的行为）：

* 回滚**先判断链路是不是已经好了**，好了就一个字都不动；没好才按开机前记下的那个
  `network_id` 定点 `select_network`，不再"全部 enable + reassociate"。
* `connect` 在动手前写一条审计：`reload=[常驻进程的回话] runtime_id=… was_id=… bss=yes/no
  scan_rows=… state=…`。上一版这里有个静默失败：`if [ -n "$id" ]` 没有 `else`，网络没被加载时
  脚本会跳过 `select_network` 然后干等 40 秒——"什么都没尝试"正好是 10-12 早上那个形状。
  现在这四种原因（reload 被拒 / 块没变成运行时网络 / BSS 不在扫描表里 / 驱动拒扫描）能分开。
* `driver_reset` 第一步改成**在总线上重插**：`echo 0 > …/authorized` → 2 秒 → `echo 1`，
  并且记录网口是否真的消失又回来；重载模块退居第二步。这才是"断电重插"在软件侧最近的等价物，
  而它**仍然没测过**——今晚第一次有代码走到这里，走的是那条被证伪的老路。

审计文件故意不放 `/run`：这套东西的意义就是"卡回到电脑上之后还能读到刚才发生了什么"，
`/run` 是 tmpfs，一重启就没了。文件里**不写口令**，只写 SSID 和常驻进程的回答。

### 顺着这条线又抓到一条：这张卡的 `wpa_cli status` 打的是 `id=`，不是 `network_id=`

`restore_snapshot` 需要"刚才连的是哪个网络"的运行时 id，我先写了 `/^network_id=/`（新版本
wpa_supplicant 的写法）就提交了 —— 这是个**没测过的假设**，而它的失败方式恰好是我这次要消灭的那种：
解析永远返回空，回滚每次都悄悄走 fallback，屏上什么都看不出来。

对着卡上的二进制验，两个独立来源同意：

```
dpkg status                     : wpasupplicant 2:2.11-0ubuntu5
strings /usr/sbin/wpa_supplicant: wpa_supplicant v2.11
格式串 `network_id=%` 出现次数   : 0
                                 : 却有 id=%d / id=%u
```

所以这台机器印的是 `id=`。现在两种写法都吃，并且拿**文件里那行字面 awk**（不是塞进变量的正则——
那样 awk 会当成表达式报语法错；也不是 `${!var}`——那是 bash 的间接展开，用 `sh` 跑直接死）过了四种输入：
`network_id=0` → `0`，`id=0` → `0`，`DISCONNECTED` → 空，只有 `id_str=`/`prev_id=` 的行 → 空。
**这两次失败都在我的测试脚本里，如果我不看它们报了什么的就照抄结论，"解析有 bug"这条假新闻就写进仓库了。**

至于"为什么 select_network 之后连 aqk 都没尝试"，审计行加上之后的**第一次上机就回答了，而且答案是
我自己的 bug**：

```
2026-10-12T00:38:42Z connect ssid="aqk" reload=[Unknown command 'reload_config']
                     runtime_id=none was_id=0 bss=yes scan_rows=4 state=COMPLETED country=CN
```

**`wpa_cli` 里没有 `reload_config` 这个命令。** 对着卡上的二进制问得清清楚楚：
`/usr/sbin/wpa_cli` 里有 `reconfigure`、`add_network`、`select_network`、`remove_network`、
`enable_network`、`save_config`，**没有** `reload` 也没有 `reload_config`；daemon 侧
`wpa_supplicant` 里有 `RECONFIGURE`、`reload_config` 出现 0 次。也就是说这个脚本从写出来那天起，
每一次"让常驻进程重读文件"都在回 `Unknown command`——而我把回话丢进了 `/dev/null`，所以在日志里
"命令不认识"和"命令照办了"长得一模一样。

于是整条因果闭上了，而且和芯片、和口令、和 aqk 那个路由器都没有关系：

* conf 文件写对了（`put_network` + `validate_conf` 那一路是好的）；
* 那个 AP 在扫描表里看得见（`bss=yes`、`scan_rows=4`）；
* 但常驻进程**从来没被告知有新网络**，所以 `network_id_for "aqk"` 是空的；
* 上一版这里正好是 `if [ -n "$id" ]` 没有 `else`——静默跳过 `select_network`，然后干等 40 秒；
* 屏上就是"连接失败"，口令一次都没被检验过。

现在连接**根本不动文件**：`add_network` → `set network <id> ssid/key_mgmt/psk/proto/ieee80211w/
scan_ssid` → `enable_network` → `select_network`，每条命令的回话都进审计；参数被拒就是立刻失败，
不再等 40 秒。文件只在**已经连上之后**写，用来活过重启；那一步要是被 `validate_conf` 挡了，审计会
写"连上了但没能存盘，重启后不会自动连"——因为"连接成功"以前会被读成"已保存"。

同一类问题在 `connect_saved` 里也有一份：那里也写着 `reload_config`（同样是假命令），现在换成
`reconfigure` 并且记回话。它后面那句无条件的 `reassociate` 也删了——`select_network` 本身就是断开再
重连，在这块芯片上多做一次断开就是"重新连上"和"卡住"的区别，这条今天刚在回滚路径上量过。

**口令泄露那条不变量也顺手做严了。** 原来的检查是 grep 关键字 `psk`，于是 `psk_r`（回话变量）也会被
`$psk` 匹配上——它同时造成了一个假报警和一个歧义的审计字段名。现在回话一律叫 `*_reply`，检查改成
词边界：`audit`/`err` 里不许展开 `$psk`；文件里仍然有 3 行引用 `$psk`，全是必须引用它的那三条
（判空、`set psk` 本身、成功后 `build_block` 存盘）。

还**没测**的一件事：`add_network` + `select_network` 这条路能不能真的连上 aqk。差一次上机，而审计行
会说明剩下哪种可能。

现场处理仍然是离线做的：原 conf 备份在构建机 `/root/card-conf.before-aqk-removal`，脚本的
上一版备份在卡上 `/root/wifictl.pre-reset`，再上一版 `/root/wifi-conf.pre-wifictl*`。


**还有一件要记住的事：ES 的 ERROR 行会带整条命令，里面是明文口令。** 上面 `executeScript()`
那句 INFO 不落盘，但失败时的 `LOG(LogError) << "Error executing " << command` 会，实测卡上
`/root/.emulationstation/es_log.txt` 里就有连着 SSID 和口令的行（现在计数：日志文件 1 行、
journal 3 行 —— 子进程 stderr 也会被 `r36-es` 转出去一份，所以不止一处）。文件是 root 0600 目录下的，
和 FAT 上明文的 `wifi.txt`、菜单写进 conf 的 `psk="…"` 是同一档暴露，没有更大口子 —— 但排查时
别把这份日志贴到公开场合。（我只做了计数，没有动用户的日志文件。）





