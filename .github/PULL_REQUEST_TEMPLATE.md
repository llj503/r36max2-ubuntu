## 改了什么 / 为什么

## 在真机上验证过吗
这块板子的结论只认实测。请写清楚：跑的是哪个 `tools/...` 或 `scripts/...`，
以及看到的具体输出（不要只写"能用"）。

## 检查清单
- [ ] `make lint` 通过
- [ ] 没有提交镜像、第三方源码、`wifi-cred.txt`、任何密码或 SSH 主机密钥
- [ ] `.sh` / `.dts` / `.service` 保持 LF（见 `.gitattributes`，CRLF 会让板子上 `bash: /bin/bash^M`）
- [ ] 动过 `projects/r36max2/dt/` 的 GPIO 极性标志 → 同步确认 joypad 驱动的 gpiod 转换
      （`projects/r36max2/patches/`），两者是耦合的：dtb 不匹配时模块能加载、能注册
      input 节点，然后什么都不上报
- [ ] 动过 `packages/` 里的东西 → 说明装到板子上后怎么验证
- [ ] 新增文件放在了对的目录（角色划分见 `CHANGELOG.md`），没有放回 `build/`
