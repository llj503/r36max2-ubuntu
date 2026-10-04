# 内核版本：7.2.8（v21 镜像里唯一内核），6.12.79（历史）

[← 返回 README](../../../README.md)

主线 7.2.8（2026-09-25 发布）在这块板子上**已经跑通并真机验证**（显示、音频、GPU、
WiFi、摇杆 17 键 + 4 轴 + 震动全部实测）。**v20 起默认内核是 7.2.8；v21 起镜像里只有它**
—— 6.12.79 曾作为"改一个文件名就能退回"的保险整套装在卡上，代价是第二棵模块树、第二份
dtb 和 `boot-612.ini`，而这四份文件互相配错的可能性比它防的故障更多。要回到 6.12.79 就从
git 历史取那版打包器（`git show 54332c2:scripts/pack-v20.sh`）重新出镜像。唯一还需要小心的是
weston —— 见 [WAYLAND.md](WAYLAND.md) 里那条 ⚠️，它只在开合成器时才会发作，所以图形栈装了但默认不启动。

| | 6.12.79 | 7.2.8 |
| --- | --- | --- |
| 构建 | `K=/root/r36/linux-6.12.79 bash scripts/build-all.sh` | `K=/root/r36/linux-7.2.8 bash scripts/build-all.sh`（16 核 505 秒） |
| 补丁层 | 全部干净应用 | 11/24 干净；13 个 panfrost 冲突**直接丢掉**（上游已实现 `SET_LABEL_BO`、`SYSTEM_TIMESTAMP`） |
| 显示 / 音频 / GPU / WiFi | ✅ | ✅（WiFi 需下面的兼容补丁） |
| 摇杆 joypad | ✅ | ✅（需下面的 gpiod 改写 + 配套 dtb 极性） |

7.2.8 需要四件事，都在这里：

1. **`scripts/k72-prepare.sh`** —— 打补丁 + 把 Rocknix 的 `panel-generic-dsi.c` 搬进
   `drivers/gpu/drm/panel/`（主线没有 `rocknix,generic-dsi`），并把它挂进 Kconfig。
   两个坑：Kconfig 条目必须在最后一个 `endmenu` **之前**，且依赖名是 `DRM_MIPI_DSI`
   而不是 `MIPI_DSI` —— 写错时 `scripts/config --enable` **静默无效**，症状是面板驱动
   根本不编译，开机黑屏。
2. **面板驱动适配新 DRM 接口**：`hex2bin` 移到 `<linux/hex.h>`；`drm_panel_init()`
   不再是驱动可用接口，改用 `devm_drm_panel_alloc(dev, struct generic_panel, panel,
   funcs, DRM_MODE_CONNECTOR_DSI)`，它返回 **ERR_PTR**（不是 NULL），所以判空要写
   `IS_ERR/PTR_ERR`。
3. **`projects/r36max2/patches/aic8800-7.2.8-compat.patch`**（221 行，4 个文件）—— 给 radxa-pkg 那份
   AIC8800 驱动打上游 API 搬家补丁：`cfg80211_ops` 十几个回调首参
   `net_device *` → `wireless_dev *`（用转发 wrapper，不动函数体）、
   `cfg80211_new_sta/del_sta` 收 wdev、`get_tx_power` 多 `radio_idx`/`link_id`、
   `remain_on_channel` 多 `rx_addr`、`in_irq()` → `in_hardirq()`、
   **`strncpy()` 已从内核移除** → `strscpy()`、`ieee80211_mgmt` 的 action 内层 union
   变匿名且 `action_code` 上提。打完 `make -C drivers/aic8800 KDIR=<tree> modules`
   零 error，产物与真机验证过的那份**逐字节相同**。
4. **`projects/r36max2/patches/joypad-gpiod.patch`**（473 行，24 个 hunk，两个文件）—— 把
   `rocknix-singleadc-joypad.c` / `rocknix-joypad.c` 从整数 GPIO API 改写成 gpiod
   消费者 API，同一份源码在 6.12 与 7.x 都能编。改写本身不难，难的是它牵出两个
   **完全静默**的坑，值得单独写清楚：
   - **`gpiod_set_value()` 会按设备树极性取反，`gpio_set_value()` 不会。** 逐行改名
     等于把每一个 `GPIO_ACTIVE_LOW` 脚的电平反过来。这块板子上：ADC 复用器的
     `amux-en`（低电平才接通）被反过来 → 复用器全程断开，四根轴和电压梯按键全读
     悬空脚；地址位 `amux-a` 被反过来 → 每次选通道都选错。现在的约定写死在
     `projects/r36max2/dt/rk3326-xifan-r36max2.dts` 的注释里：地址位声明 `ACTIVE_HIGH`（逻辑==物理），
     `amux-en` 保留 `ACTIVE_LOW` 而驱动改成**逻辑断言**（接通写 1），`rumble-gpio`
     实测高电平转 → `ACTIVE_HIGH`。
   - **裸的 `gpios` 属性必须传 `con_id = NULL`。** gpiolib 用
     `gpio_suffixes = {"gpios","gpio"}` 拼候选名：con_id 非空时只找
     `"<con_id>-gpios"` / `"<con_id>-gpio"`，con_id 为 NULL 才找裸 `gpios`。传字符串
     `"gpios"` 就变成去找 `gpios-gpios`，永远 -ENOENT；而这段代码对 -ENOENT 是
     **故意容忍**的（desc 置 NULL 继续跑），于是模块加载正常、17 个键码都注册进
     input、`/sys/kernel/debug/gpio` 里一个消费者都没有、dmesg 一条错都不打。
     顺带解释了一个假象：厂商 DT 把震动写成单数 `rumble-gpio`，正好命中第二条后缀，
     所以 `devm_gpiod_get_optional(dev,"rumble",...)` 看起来"能用"。
   - **改 DT 极性必须重启才生效，重载模块没用；只改驱动则 `rmmod` + `modprobe` 即可。**
   - 判定手法：`cat /sys/kernel/debug/gpio` 看 label 有没有被认领，比读代码猜错误码快得多。
     抓事件用 `tools/input/diagnostics/k72-evcap.sh` + `tools/input/diagnostics/k72-evread.sh`（注意本机 evtest 1.36
     **没有 `--raw`**，带上它只会写一份 usage 进文件；正常模式事件行是
     `type 1 (EV_KEY), code 304 (BTN_SOUTH), value 1`，`value` 前有逗号）。
   - 真机结果：17 个 GPIO 键 down/up 全部成对，四根轴 `ABS_X/Y/RX/RY` 满行程 ±1800，
     `adc-keys` 的音量加减正常，震动用 `packages/gpu-demos/r36-rumble.c` 走标准 FF 通路验证
     （焊盘 hi=转、随后回 lo=停；`struct ff_effect` 在这个 ABI 上是 **48 字节**，
     自己拼缓冲区会 EFAULT，所以在设备上用 `<linux/input.h>` 编译最稳）。

**BOOT 分区上的文件名**（u-boot 2017.09 只认 `boot.ini` 这一个文件名，也不接受把
`${var}` 当文件名用，所以每个变体都是一份完整的字面文件）：
`Image`、`rk3326-xifan-r36max2.dtb`、`uInitrd`、`boot.ini`，外加
`rk3326-xifan-r36max2-usbhost.dtb` / `boot-usbhost.ini` 这一对试 Type-C 插键盘用的。
`pack-v20.sh` 在压缩前会把每个 `boot*.ini` 里 `load mmc 1:1 …` 点名的文件逐个确认
**真的在这张卡上**——写错一个名字就是黑屏，而这台机器没有串口去读那条错误。
