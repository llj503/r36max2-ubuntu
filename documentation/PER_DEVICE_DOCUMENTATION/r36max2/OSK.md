# 虚拟键盘（r36-osk）：没有键盘时怎么打字

[← 返回 README](../../../README.md)

Ubuntu 26.04 里**根本没有可用的屏上键盘**：`wvkbd`/`fsvkbd`/`svkbd` 都没有打包，
`onboard`/`matchbox-keyboard` 是 X11 程序而这台机器上没有 Xwayland；更要命的是
**weston 14 不实现 text-input-v3**（foot 开机就自己说：`text input interface not
implemented by compositor; IME will be disabled`），所以"输入法风格"的键盘没有对话对象。
`packages/r36-osk/r36-osk.py`（装成 `/usr/local/bin/r36-osk`）改用两个本机已验证的机制拼起来：

- **`/dev/uinput` 造一个真键盘**：weston/libinput 立刻把它认成
  `r36 on-screen keyboard: device is a keyboard`，发出去的是硬件事件流，
  所以**任何客户端都收得到**，不依赖合成器的文本输入协议；
- **`wofi --show dmenu --columns N` 当按键网格**。两个必须记住的实测事实：
  wofi v1.5.1 **没有 `grid`/`dgrid` 这种模式名**（会打
  `I would love to show grid but Idk what it is` 然后退出），网格是 dmenu 模式加
  `--columns` 出来的；而 weston **不提供 `wlr-layer-shell`**，wofi 于是自动退化成
  普通窗口（`switching to normal window mode`）——正好是我们要的。
- 字符怎么进对窗口：wofi 只在被 map 期间持有键盘焦点，**它一退出 weston 就把焦点还给
  上一个表面**，所以节奏是"点一个键 → wofi 关闭 → 敲进当前焦点 → 重开"。一次一个字符，
  和拇指推摇杆的速度本来就匹配。

页面是三页 10 列（面板 1024×768，格子 94×82 px）：`letters`（数字行 + qwerty 三行 +
`SHFT/#!?/CAPS/SPC/DEL</>DEL/RET/X`）、`symbols`、`nav`。`SHFT` 是**只 latch 下一个键**，
`CAPS` 是切换，状态写在网格顶部的 prompt 里。用 `<word>` 表示动作、并且只认
"完整尖括号"这一条很重要：符号页上 `<` 和 `>` 本身是按键，早期版本用 `startswith("<")`
判断动作，结果点 `<` 会解析成空动作、什么都不打。

- 用法：`r36-osk`（默认字母页）、`r36-osk --start symbols`、
  `r36-osk --type 'Hello, 36!'`（不开网格、纯打字，脚本可用）、
  `r36-osk --list`（打印键位表）、`r36-osk --probe-grid 6`（**不开 uinput**，只验证
  网格真的能显示——成功标志是 wofi 撑满 6 秒不退出，即 rc=124）、
  `r36-osk --dry-run`（打印它准备执行的 wofi 命令行）。
- 没人点的时候**不要退出**：`--pick-timeout`（默认 1800 秒）到点就重开网格。
  第一版把 `subprocess` 的 600 秒超时当成"用户退出"，于是键盘在没人点的 10 分钟后
  静默消失，测试时看起来像"网格根本没起来"。
- 启动时会先数内核里的 flip/vblank stall 条数并**大声警告**屏幕可能已经冻住
  （见 [WAYLAND.md](WAYLAND.md) 的 weston 卡死一节）——不然就会出现"让人对着一个根本不刷新的屏幕点击"这种事。
- 不需要屏幕也能验证：`tools/capture/k72-osk-headless.sh` 用一个假的 wofi（`/tmp/oskstub/wofi`
  按脚本吐出按键标签）驱动真 uinput 键盘，再用 `tools/capture/r36-evsnap.py`
  （装成 `/usr/local/bin/r36-evsnap`）从 `/dev/input/eventN` 抓回原始 `EV_KEY` 流逐条比对。
  实测 `h i SHFT a RET #!? @ SPC DEL< X` 产生的按下序列
  `h(35) i(23) SHIFT(42) a(30) ENTER(28) SHIFT(42) 2(3) SPACE(57) BACKSPACE(14)` 与期望**完全一致**，
  没有卡键、SHIFT 两次按下都释放、退出后 uinput 节点自动消失。
  比对时按**键名**取码（`osk.K["2"]`），不要手写数字：`KEY_1=2、KEY_2=3`，
  我正因为硬编码成 2 而误报过一次 FAIL。
  离线那一层还有 `tools/input/verify/k72-osk-maptest.py`（重复项检查、动作/按键解析、shift 语义、
  格子尺寸是否够拇指点）。
- 还没做完的一步：**真人用摇杆点网格**（要屏幕能用）。落点用
  `foot -- sh -c 'stty -icanon; cat > /tmp/osk-typed.txt'` 抓住，SSH 直接读回，
  不依赖任何人看屏幕判断（`tools/input/diagnostics/k72-osk-live.sh` + `k72-osk-read.sh`）。
