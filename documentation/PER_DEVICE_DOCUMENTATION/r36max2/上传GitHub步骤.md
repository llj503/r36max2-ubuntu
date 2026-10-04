# 把 E:\ubuntu 传到 GitHub —— 操作步骤

本机现状（我已经查过）：Git 2.52.0（带 Git Credential Manager，`credential.helper=helper-selector`）、
`gh` 没装、`~/.ssh` 里还没有密钥、github.com 走 HTTPS 可达（200）。
仓库已经在 `E:\ubuntu` 初始化好，`.gitignore` / `.gitattributes` / `LICENSE`(GPL-2.0) / `README.md`
都写完了，209 个文件约 1.4 MB 已 `git add`，**只差提交身份和推送**。

## 你需要做的（浏览器登录那条路，最省事）

### 1) 在网页上建一个空的私有仓库

打开 <https://github.com/new> →
- Owner：你的账号
- Repository name：`r36max2-ubuntu`（随你）
- 选 **Private**
- **README / .gitignore / license 三个框都不要勾**（本地已经有了，勾了会产生冲突提交）
- Create repository，然后把页面地址记下来：`https://github.com/<你的用户名>/r36max2-ubuntu.git`

### 2) 告诉我两样东西（或者自己填进下面的命令）

- GitHub 用户名
- 提交要用的邮箱（想避免暴露真实邮箱就用 `<用户名>@users.noreply.github.com`）

### 3) 提交 + 推送

```bash
cd /e/ubuntu
git config user.name  "你的GitHub用户名"
git config user.email "你的邮箱"
git commit -m "R36 Max 2 (RK3326): mainline 6.12 + Ubuntu 26.04 port, board DTS, image scripts, GLES2/GBM demo"
git remote add origin https://github.com/你的用户名/r36max2-ubuntu.git
git push -u origin main
```

`git push` 第一次会**自动弹出浏览器**让你登录 GitHub 并授权（Git Credential Manager 走的
OAuth），点几下就好，之后凭据存在 Windows 的凭据管理器里，不用再登录。
如果弹的是"Sign in with browser"以外的窗口（比如让你贴 token），把窗口截图发我。

## 想改用 SSH（可选，以后推很多仓库时更顺）

```bash
ssh-keygen -t ed25519 -C "你的邮箱"          # 一路回车
cat /c/Users/llj/.ssh/id_ed25519.pub          # 复制这一行内容
```
贴到 <https://github.com/settings/keys> → New SSH key → 保存，然后：
```bash
cd /e/ubuntu
git remote set-url origin git@github.com:你的用户名/r36max2-ubuntu.git
ssh -T git@github.com                          # 看到 "Hi 用户名!" 就通了
git push -u origin main
```

## 万一你更想用 token（Fine-grained PAT）

<https://github.com/settings/personal-access-tokens/new> → 只勾这一个仓库、
Contents: Read and write → 生成后复制。push 时用户名填你的 GitHub 用户名，
密码那一栏粘 token（**别把 token 发到聊天里**，直接粘贴到终端就行）。

## 传完之后

- 以后每次改动的常规流程：`git add -A && git commit -m "..." && git push`
- 想加设备照片/日志之外的东西，先看一眼 `.gitignore`：镜像、第三方源码、WiFi 口令、
  `artifacts/`、`logs/` 都是故意排除的，别用 `git add -f` 强行加回来。
- 换电脑或改密码后凭据失效：`git credential-manager github logout`（或删掉
  「控制面板 → 凭据管理器 → Windows 凭据」里 `git:https://github.com` 那条）。
