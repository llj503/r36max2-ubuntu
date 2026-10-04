# Wayland（weston）：让屏幕显示图形界面

[← 返回 README](../../../README.md)

选型是 **weston 14.0.2**（Ubuntu 26.04 里的参考实现），`--backend=drm` 直接从
GBM/panfrost 起，不需要 X 或别的合成器垫在前面。内存实测：weston 常驻 53 MB（peak
58.8 MB，单元上挂 `MemoryHigh=320M` 只限速不 OOM），同时开着 `foot` +
`weston-simple-egl` + `weston-flower` + `wofi` 之后仍有 ~580 MB available。

- 安装：`apt install weston wayland-protocols libwayland-dev grim wf-recorder foot wofi
  cmake pkg-config`。Ubuntu **没有 `weston-examples`** 这个包，示例客户端
  （`weston-simple-egl`、`weston-flower`、`weston-screenshooter`）都在 `weston` 包里；
  而 apt 只要遇到一个不存在的包名就**整条命令什么都不装**（`E: Unable to locate package`
  后面紧跟着一句看起来像成功的 `apt exit=0`），所以 `scripts/k72-wayland-install.sh`
  先用 `apt-cache policy` 过滤再安装。
- 落地的文件（都在仓库里，装完设备与将来出镜像用同一批）：
  `packages/wayland/weston.ini` → `/etc/xdg/weston/weston.ini`；
  `packages/wayland/weston.service` → systemd 单元，**默认 disabled**，因为合成器一拿 DRM master
  就会把 tty1 的状态页顶掉；
  `packages/wayland/r36-wayland` → `/usr/local/bin/r36-wayland`（`start|stop|status|run <app>|egl|
  term|smoke [秒]|shot|apps|env`）；`packages/wayland/zz-r36-wayland.sh` → `/etc/profile.d/`，只在
  socket 存在时导出 `XDG_RUNTIME_DIR=/run/wayland WAYLAND_DISPLAY=wayland-0`。
- 用法：`r36-wayland start` → `r36-wayland run foot`（或 `r36-wayland smoke 30` 摆两个
  GL 客户端）。从 SSH 起的程序直接显示在屏幕上，这就是这台没键盘的机器的日常姿势。
- 三个实测坑：
  1. **weston 14 已经没有 `--tty=` 选项**。`fatal: unhandled option: --tty=/dev/tty2`
     发生在 backend 已经初始化、DSI-1 已经 modeset、EGL config 都选好之后，所以日志看着
     像成功，进程却立刻退出。VT 由 session/libseat 决定；以 root 跑 systemd 服务直接就能
     拿到 DRM master（配 `Conflicts=getty@tty1.service` + `ExecStopPost=chvt 1` 让控制台回来）。
  2. **截图被合成器的权限模型挡住**：`weston-screenshooter` 回
     `Output capture error: unauthorized`，`grim`/`wf-recorder` 需要
     `wlr-screencopy-unstable-v1`（weston 不实现）。libweston 里
     `weston_compositor_add_screenshot_authority` 只把捕获权交给"由用户按键触发的那次请求"，
     ini 没有开关；`tools/capture/r36-shot.py`、`tools/capture/r36-shot2.py` 试过直接请求、先挂请求再注入
     6 种组合键、全盘找新文件，都没能拿到 PNG。**所以图形验收目前仍然靠眼睛/拍照。**
  3. **意外收获：`/dev/uinput` 虚拟键盘这条路是通的**（uinput 内核内建，不需要模块）。
     `r36-shot.py` 造出键盘后 weston 立刻记录
     `event4 - r36-shot-virtual-keyboard: is tagged by udev as: Keyboard` 并把它关联到
     DSI-1 —— 这正是以后做"摇杆→键盘/鼠标"桥的现成地基。结构体大小有讲究：
     `struct uinput_user_dev` 的 abs 数组是 `__s32`，`ff_effects_max` 后面**没有填充**，
     总共 80+8+4+4×64×4 = **1116 字节**，写 1120 直接 `EINVAL`。
     注入按键时还顺手撞开了 weston 的 flight recorder（`Ctrl+Alt+P` 起 / 再按停，
     30 秒写出 `/capture.wcap` 10 MB、524 帧，magic `PACWXR24`），那是合成器侧调试的现成数据源。
- **⚠️ 7.2.8 上 weston 会把显示管线永久卡死（真机踩到，只有重启能清）**：weston 启动日志里就写着
  `DRM: does not support Atomic async page flip`（RK3326 的 VOP 没有原子异步翻页），于是内核走
  `drm_atomic_helper_commit_tail_rpm` 这条**在提交里同步等 vblank** 的退路。跑了 23 分钟、
  客户端退出拆面的时候出现第一条 `WARNING drivers/gpu/drm/drm_atomic_helper.c:1921 ... wait_for_vblanks`，
  之后 `rockchip-drm: vblank wait timed out on crtc 0` / `flip_done timed out` /
  `[CRTC:39:crtc-0] commit wait timed out` 每 10–40 秒循环，面板冻在最后一帧（看起来是"白屏带四角暗块"）。
  **停 weston、`chvt 1`、写 `fb0/blank=0` 都救不回来**，vsync 中断已经不再来了。
  **加上 `[core] pageflip-timeout=500` 后的复测**（`tools/gpu/runtime/flip-churn.sh`：8 轮 × 12 秒、每轮把
  EGL 客户端 SIGKILL 掉复现"拆面"；`tools/host/verify/flip-soak-host.sh`：12 分钟、每分钟起停一次客户端）：
  内核四个 flip/vblank 计数**全程 0 增量**，weston 一直活着，stop 之后控制台自动回来。为了不让
  "客户端根本没挂上"冒充成功，脚本先用 weston 的累计 CPU 时间证明真在合成——空闲 15 秒 ΔCPU=0 秒，
  带 `weston-simple-egl` 15 秒 ΔCPU=2 秒，浸泡期间每分钟稳定 +2.5~3 秒。
  **这还不算结论**：那次是连续跑约 23 分钟才发作，12 分钟没覆盖到；而且有个更值得怀疑的触发条件没排除——
  卡死之前我曾**在翻页正飞的时候硬杀过上一个 weston**（日志原话：`destroying output DSI-1 (id 0) with a
  pending flip, but as we are shutting down we can't wait to destroy it when the flip completes`），
  所以"23 分钟"可能只是延迟，真正弄丢 vsync 中断的是那次中途硬杀。
- **但"中途硬杀"这条已被证伪，同时"只有重启能救"被证实**（2026-10-03 下午第二次发作）：
  专门造的三个复现工具（`tools/gpu/runtime/kill-midflip.sh` 在 flip 飞行途中 SIGKILL、当时的 `k72-sigtermflip.sh` 换
  SIGTERM、`r36-fatalabort-device.sh` 让客户端自己 abort）全部**没能**弄丢 vsync；而第二次卡死发生在
  `pageflip-timeout=500` **已经生效**、屏幕**完全静止**（foot + 一个没人点的 wofi 网格，没有任何客户端
  起停）约 23 分钟的时候。于是"拆面"和"硬杀"两个触发假设都死了，剩下的嫌疑人只有"跑了多久"和
  "长时间静止一帧之后 vsync 不再来"。
  发作后的两组硬数据把恢复手段钉死了：① **停掉 weston 之后内核仍在报**
  `Workqueue: events drm_fb_helper_damage_work` → `drm_crtc_wait_one_vblank` 超时——**是 tty1 控制台刷字
  在等 vblank**，说明 vsync 已在 VOP/内核层消失，与合成器无关；② 重新 `systemctl start weston` 后，
  weston 每一帧都被拒：`atomic: couldn't commit new state: Device or resource busy` +
  `repaint-flush failed: Device or resource busy`——那条卡死的 commit 还占着 CRTC 状态。
  **所以 weston 重启不救，只有重启机器能救**（判定脚本：`tools/misc/diagnostics/wedge-probe.sh` 停合成器后裸测翻页、
  `k72-wedge-state.sh`（看是否还有新 stall）、`k72-restore-weston.sh`（收尾）——后两个是当时的临时脚本，已删，git 历史可取回）。
  测量工具是 `packages/gpu-demos/r36-flipprobe.c`（装成 `/usr/local/bin/r36-flipprobe`）：dumb buffer +
  `drmModePageFlip(DRM_MODE_PAGE_FLIP_EVENT)` + poll 计时，健康时 40 次翻页平均 1.7 ms、最大 16.6 ms；
  管线卡死时它自己会**阻塞在内核里不返回**（连 3 秒超时的打印都出不来）——这本身也是个信号。
  两个恢复陷阱：`weston.service` 的 `ExecStopPost=chvt 1` 在装 `kbd` 之前
  是**静默失败**的（这镜像原本没有 chvt/fgconsole，所以"active vt"一直打印空）；刚开机
  `fb0 blank` 读数是 4（DPMS 关闭），往 tty1 写一次东西才亮——**没键盘的机器上"屏黑"和"死机"
  长得一模一样，别急着长按电源**。
- 刻意设置的：`locking=false` + `idle-time=0` —— 这台机器睡眠进得去出不来，一个锁掉的
  屏等于把设备关小黑屋；`gbm-format=xrgb8888` 与之前 GBM/EGL 验证选到的格式一致；
  光标缺 `dnd-*` 只影响拖拽图标，无功能性问题。
