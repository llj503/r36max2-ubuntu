# distributions/ —— 发布记录

镜像本体（约 400 MB 压缩后）不入库：仓库只放每一版的 sha256。**也不作为 Release 附件
公开上传**——镜像里含 AIC8800DC 的厂商固件 blob，分发它等于分发别人的二进制，所以想要
镜像就按 [BUILD.md](../documentation/PER_DEVICE_DOCUMENTATION/r36max2/BUILD.md) 自己构建，
产物落在 `target/`，再用下面这列哈希对一遍。

**同一版镜像重建一次哈希就变一次，而它记在两个地方**：下面这张表和同名的
`<文件>.sha256`。2026-10-08 发现这两处已经不一致了（`6a472e1` 只改了 `.sha256`，表里还是上一版
的哈希），所以改的时候**两处一起改**。

| 文件 | sha256 |
| --- | --- |
| `r36max2-ubuntu-v2.img.xz` | `a3b0ccf69faea8747351a91a7efdc48573644d74a1e69222edacedb4514c0b81` |
| `r36max2-ubuntu-v3.img.xz` | `273b24b07001db783b0124eed8e51a7798c14959e33d741c18e29bf0730c01ed` |
| `r36max2-ubuntu-v4.img.xz` | `cb958357dd2be58224eedb8e34d15df762c94f3c03f29a3023f602b6dabd324b` |
| `r36max2-ubuntu-v5.img.xz` | `94d2ffba82ec810c1950697c29046e20e869482afdea7c88fe8d0a3828e48b72` |
| `r36max2-ubuntu-v6.img.xz` | `0c70f2b3fbc8c078691b4a553ce52d0ba35eabcc1b47dc245e61ee4c349e3acd` |
| `r36max2-ubuntu-v7.img.xz` | `83b29fe491f7768d855ef8ec36477fdd98eb5dab47f1afdf80c998e3fe417177` |
| `r36max2-ubuntu-v8.img.xz` | `8da7a9f31aa440ebb6438644aeb3a5a1027a39ff3c00867b3857ccb6e57dbabf` |
| `r36max2-ubuntu-v9.img.xz` | `237502d2ab4725b97825a83ed43a8c0438953fed95e883b390849f06df731a89` |
| `r36max2-ubuntu-v10.img.xz` | `2e58e8856f8547c64a01b7be9ee1bfe4abcc57002f96831b6e0d3cc549d7a122` |
| `r36max2-ubuntu-v11.img.xz` | `1b71f49629681fe41c1e4fee5cbe20cade7c67fc08ab16258cd4e32d1046f5d9` |
| `r36max2-ubuntu-v12.img.xz` | `ef96e54aaa579a593692264d5dedb79017802668ebb0fc171153322074cd003d` |
| `r36max2-ubuntu-v13.img.xz` | `2bec091285eb59e3dc51f5c4691f89ddb1f7228a69501ef3721fe3cc61a73be7` |
| `r36max2-ubuntu-v14.img.xz` | `ae1a938a0f97c7221a2671124b71be8cbe25f2b525d37ec303a4dc3be31a605d` |
| `r36max2-ubuntu-v15.img.xz` | `30af53c3474e36eefada0e5d7c03627fb30585cd74c1e99081e556b8bbef7dfb` |
| `r36max2-ubuntu-v16.img.xz` | `6e19d6068c60aa1d475009b1b7bb6df39ba898d1a2d43f5ba721ffa478471ee3` |
| `r36max2-ubuntu-v17.img.xz` | `5290cc9665d40349998b8cf1e210b88f06cd7c19ab134e5e5b90ae58171f269a` |
| `r36max2-ubuntu-v18.img.xz` | `da2a12b30a0bbe4b6a1bc6f48d00f41b8e61ab57f98cf9e690482aade0c71510` |
| `r36max2-ubuntu-v19.img.xz` | `ea1aa41ea33d56b467d2100c333baf8d6c0f55c7cd00b99b63e56a8d018cb282` |
| `r36max2-ubuntu-v20.img.xz` | `da46854618144d70b49d47cf54ad7aa81bbf59922636e2670c4cbb2e2f66a143` |
| `r36max2-ubuntu-v21.img.xz` | `7d5cc138d1aad7b992ba21062f08d877e46453bd054b11f9d5174a29b3362078` |
| `r36max2-ubuntu-26.04.img.xz` | `c0df67ce40f27392d8a9d94a6016754f747a0dd87a3be2e499362bf0d699b64a` |
| `r36max2-ubuntu-alt-arkosblobs.img.xz` | `360ac81678b1344302844d2e89fea541033692c02577de8a15fb65ad12e968d8` |

**v21 这条哈希（`7d5cc138`，2026-10-09，839669512 B）记的是"当前这棵树产出的镜像"，
它还没被刷进卡里做首启验证**。里面比上一版多了四样，都是当天实测出来的修复：ES 按
`type=` 而不是名字找电池、GPU governor 保存函数不再对空列表调 `getSelected()`
（那个 `rc=134` abort 就是它，也是"改语言存不下去"的直接原因）、35 个 gettext catalog
加一个非 C 载体 locale、以及启动器先清空 `LC_MESSAGES/LANGUAGE` 再决定语言并在
`Language` 真的变化时重开 ES。

手上那张卡跑的是同一版 v21 镜像 + 当场手工应用的这些修复（ES 二进制 sha `b6b968cd`，
旧的二进制备份在卡上 `/root/emulationstation.pre-{battery,guard}`）。刷过并开机验证过
之后再来对这一行。

**镜像内容只由配方决定，`scripts/image` 里那些自检不改一个字节**，所以加断言不需要重打；
这一版是带着断言之前打的，但断言对着它实际跑过一遍（只读挂载那张 .img：launcher 两处标记
齐全、镜像里的 ES 与 `install_pkg` 逐字节相同 `b6b968cd`、catalog 35、载体 locale 在），
全绿。

校验：把镜像和本目录的 `.sha256` 放同一目录后

```bash
sha256sum -c r36max2-ubuntu-v20.img.xz.sha256
```

内核与镜像的对应关系（[../documentation/PER_DEVICE_DOCUMENTATION/r36max2/KERNELS.md](../documentation/PER_DEVICE_DOCUMENTATION/r36max2/KERNELS.md)）：

- **v2–v19** —— 6.12.79 主线 + Rocknix 三层补丁，EmuELEC 之外的通用 Linux 开发环境
- **v20** —— 双内核：7.2.8 默认、6.12.79 同卡保留（改名即可回退），加 weston 会话、
  摇杆键鼠桥、`r36-osk` 虚拟键盘、无凭据/无主机密钥的发布形态
- **26.04 / alt-arkosblobs** —— 早期 base 变体与用 ArkOS 厂商 blob 打出的对照版

刷机与首启步骤见 `documentation/PER_DEVICE_DOCUMENTATION/r36max2/刷写与首启说明.md`。
