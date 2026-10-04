# 摇杆当键鼠用（uinput 桥）

[← 返回 README](../../../README.md)

`packages/r36-keymapper/r36-keymapper.py`（纯标准库）读摇杆的 evdev 节点，用 `/dev/uinput` 造一个键盘 +
一个鼠标重新发出去。内核内建 uinput，不需要模块，**也不需要合成器在跑**——验证映射的方法
就是读那两个新 event 节点，完全不碰 DRM，所以它能安全地单独使用、单独关掉。

| 摇杆 | 发出 | 实测 |
| --- | --- | --- |
| 左摇杆 | `REL_X/REL_Y`，死区 ±220、满推 24 px/tick、1.7 次曲线 | 单 tick 最大 ±24 ✓ |
| 右摇杆 | `REL_WHEEL(_HI_RES)` / `REL_HWHEEL(_HI_RES)`，每 0.16s 一格 | ±1 格 / ±120 hi-res ✓ |
| A / B / L3 | `BTN_LEFT` / `BTN_RIGHT` / `BTN_MIDDLE` | down/up 成对 ✓ |
| X / Y | `KEY_BACKSPACE` / `KEY_SPACE` | ✓ |
| 方向键 | `KEY_UP/DOWN/LEFT/RIGHT` | ✓ |
| SELECT / START / MODE | `KEY_ESC` / `KEY_ENTER` / `KEY_LEFTMETA` | ✓ |
| L / R / L2 / R2 | `KEY_LEFTCTRL` / `KEY_LEFTALT` / `KEY_LEFTSHIFT` / `KEY_TAB` | ✓ |
| R3 | `KEY_END` | ✓ |

17 个键 + 4 根轴全部实机验过，没有"只 down 没 up"的卡键。

- 用法：临时跑 `systemd-run --unit=r36-km-test /usr/bin/python3 /usr/local/bin/r36-keymapper.py -v`，
  `systemctl stop r36-km-test` 就还原；长期用则是 `r36-keymapper.service`
  （`BindsTo=weston.service` + `WantedBy=weston.service`，起合成器自动带上、停合成器自动撤）。
  默认 `EVIOCGRAB` 抓走摇杆节点，避免同一按键既当按键又当手柄；`--no-grab` 可并存，
  `--selftest` 只打印映射表不碰设备，`--dry-run` 只读不发。
- **两个必须记的坑**：① `REL_MAX` 只有 **0x0f** —— `REL_WHEEL=8`、`REL_HWHEEL=6`，
  按 27/28 传 `UI_SET_RELBIT` 直接 `EINVAL`，鼠标设备根本建不起来（键盘却是好的，
  所以现象像"只有一半能用"）；② `struct uinput_user_dev` 必须**正好 1116 字节**
  （abs 数组是 `__s32`，`ff_effects_max` 后面没有填充），多 4 字节就 EINVAL，
  且写记录要在 `UI_DEV_CREATE` 之前。
- 设计取舍：滚轮值是**格数**不是像素（第一版复用指针速度曲线，一次翻 23 格＝整页飞）；
  17 个键覆盖不了字母输入，**打字仍然要靠 SSH 或屏上键盘**。这座桥的目标是"指针 + 最常用键"，
  不是虚拟全键盘。
