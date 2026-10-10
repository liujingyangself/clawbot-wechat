# AGENTS.md — 给 AI 代理看的安装剧本

你被要求「帮我安装微信的 ClawBot」。这个文件就是完整做法。

**最重要的一条：不要自己重新设计安装流程。** 下面的脚本已经处理好了版本、权限、
密钥校验、失败回退和中文提示。你的工作是**跑脚本 + 在它停下来等人时提醒使用者**。

---

## 一句话

**没有本地副本时**（使用者只给了你仓库地址）：

| 系统 | 命令 |
|---|---|
| macOS / Linux | `curl -fsSL https://raw.githubusercontent.com/liujingyangself/clawbot-wechat/main/get.sh \| bash` |
| Windows | `irm https://raw.githubusercontent.com/liujingyangself/clawbot-wechat/main/get.ps1 \| iex` |

引导脚本会把仓库下到 `~/clawbot-wechat`（Windows 是 `%USERPROFILE%\clawbot-wechat`），
然后自动执行下面的安装脚本。

**已经有本地副本时**：

| 系统 | 命令 |
|---|---|
| macOS / Linux | `bash scripts/install.sh` |
| Windows | `powershell -ExecutionPolicy Bypass -File scripts\install.ps1` |

脚本是**幂等**的——中途失败或者中断了，直接重跑，已经装好的步骤会自动跳过。

### 必须在前台终端跑

不要用后台执行、不要重定向 stdin。安装过程要显示二维码、要使用者在
Antigravity 的登录界面按键。`get.sh` 已经把 stdin 接回 `/dev/tty` 来应付
`curl | bash` 的情况，但如果你自己包一层，别把这个破坏掉。

---

## 装的是什么

```
微信（手机扫码登录）
  └─ OpenClaw 网关（开机自启的后台服务）
       ├─ 腾讯官方微信插件 @tencent-weixin/openclaw-weixin  ← 收发微信消息
       ├─ 大脑：google/gemini-3-flash-preview（AI Studio 免费 key，原生工具调用）
       ├─ 干重活：agy（Antigravity CLI，免费，用使用者自己的 Google 账号）
       └─ 画图：google/gemini-3-pro-image-preview（可选，**要钱**）
```

---


## 你（AI 代理）必须遵守的三条

**1. 不要替使用者断言弹窗出现了。**

你看不见他的屏幕。弹窗可能被别的窗口挡住、可能因为非交互环境根本没显示。
说「屏幕上已经弹出了一个窗口」是在编造你无法验证的事实，会让使用者对着
一个不存在的窗口发呆。

正确说法是：**把终端里打印的那段提示原样转述给他**，然后问他看到了什么。
安装脚本现在会把每一条需要人工配合的提示**同时打印到终端**（带 `⚠ 需要你操作`
的黄色横幅），那段文字才是你能看到、也该转述的东西。

**2. 不要捕获输出来跑这个安装器。**

这是最容易犯的错：你用子进程跑 `install.ps1` 并捕获 stdout，于是**二维码画进了
你的缓冲区，使用者屏幕上什么都没有**。他会以为卡住了，而你会以为一切正常。

脚本现在会检测 `IsOutputRedirected` / `IsInputRedirected`，在扫码和 agy 登录
这两步之前直接停下并退出码 2，打印出让使用者自己跑的命令。**看到退出码 2 就
把那段命令原样转述给他，让他自己在终端里跑完，再重新运行安装器。**

正确做法：让使用者自己打开终端粘贴安装命令，你在旁边解释和排错。
实在要代跑，也必须是能直通到他屏幕的前台终端，不能捕获输出。

**3. 卡住的时候先看终端最后几行，不要重启安装。**

脚本停住通常是在等人操作，不是挂了。终端最后那段黄色横幅就写着要做什么。
真要查日志：

- macOS：`~/Library/Logs/clawbot-wechat-install.log`
- Windows：`%LOCALAPPDATA%\clawbot-wechat\install.log`

日志里每条提示都有 `PROMPT:` 前缀，能看出它停在哪一步。

## 流程里有 4 个地方必须真人参与

脚本会在**终端打印黄色横幅**，同时尝试弹系统对话框。终端那份是可靠的，
弹窗只是加强提醒。如果你（AI 代理）在旁边，请把终端里的横幅内容转述给使用者，
并提醒他**把终端窗口切到最前面**——否则他看不到二维码。

| # | 环节 | 使用者要做什么 | 卡住的典型原因 |
|---|---|---|---|
| 1 | Gemini 密钥 | 在打开的网页点 Create API key，复制 `AIza…` 粘回弹窗 | 没登录 Google；复制漏了几位 |
| 2 | agy 登录 | 回车选配色 → 空格取消数据共享 → 回车 → 浏览器登录 → 输 `/quit` | 卡在 TUI 里不知道怎么退出 |
| 3 | 微信扫码 | 手机微信扫终端里的二维码，手机上确认 | 终端窗口被挡住；二维码过期（约 8 分钟） |
| 4 | 画图（可选） | 决定开不开通；要开就得绑卡 | 不清楚要花钱 |

第 2 步和第 3 步**必须在前台终端里跑**，不能后台执行——它们需要键盘输入和显示二维码。

---

## 事实与限制（别自己猜）

- **图像生成没有免费额度。** [官方定价页](https://ai.google.dev/gemini-api/docs/pricing)
  对所有图像模型的 Free Tier 都写 "Not available"：Nano Banana Pro 约 $0.134/张。
  必须开通计费。所以安装器把画图做成**可选**，跳过不影响其他功能。
- **对话和 Agent 能力是免费的。** `gemini-3-flash` 有免费额度，而且支持原生工具调用，
  所以不绑卡也能有完整的 agent 能力。
- **`agy` 也是免费的**，走使用者自己的 Google 账号，不消耗上面那个 API key 的额度。
- **不要用反代 Antigravity 的 OAuth 的方案**（CLIProxyAPI 一类）。
  [Antigravity 条款](https://antigravity.google/terms)明文禁止第三方工具通过它的 OAuth 访问，
  Google 在封号。本项目用的是官方 `agy` 二进制，认证留在 Google 自己的程序里，性质不同。

---

## 装完怎么确认

```bash
openclaw gateway status            # 应该看到 running
openclaw channels status           # 应该看到 openclaw-weixin ... running
openclaw agent --message "你好"     # 应该有回话
```

然后让使用者在微信里发一条消息，看有没有回。

---

## 出问题时

1. 先看日志
   - macOS：`~/Library/Logs/clawbot-wechat-install.log`
   - Windows：`%LOCALAPPDATA%\clawbot-wechat\install.log`
2. 再看 [`docs/常见问题.md`](docs/常见问题.md)
3. 还不行就**重跑安装脚本**（幂等，不会重复装）

### 几个你可能会踩的坑

- **`openclaw` 装完找不到命令**：PATH 没刷新。macOS 新开一个终端窗口；
  Windows 用 `Refresh-Path`（脚本里有这个函数）或重开 PowerShell。
- **agy 权限配置写了但工具还是全被拒**：检查 `~/.gemini/antigravity-cli/settings.json`
  里有没有 `ask` 通配规则（比如 `command(*)`）。优先级是 **Deny > Ask > Allow**，
  通配 ask 会把所有 allow 盖掉。本项目的 `agy-permissions` 脚本故意不写 ask。
- **跨 agent 调用报 `Gateway client authority closed`**：这是 `openclaw agent` 这种
  一次性 CLI 客户端才有的问题，从微信通道发起不会。不用修。

---

## 不要做的事

- 不要改成 `--dangerously-skip-permissions`。这个 bot 微信能触达，等于把电脑交出去。
- 不要把 `groupPolicy` 改成 open。群聊是最大的提示词注入面。
- 不要把使用者的 API key 打印到对话里或日志里。
- 不要替使用者决定开不开通画图——那是花钱的事，必须他自己点。
