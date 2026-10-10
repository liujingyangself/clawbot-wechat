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

### 关于交互

安装过程要显示二维码、要使用者在 Antigravity 的登录界面按键，但这些
**安装器会自己弹窗口解决**，你照常驱动就行。`get.sh` 也已经把 stdin 接回
`/dev/tty` 来应付 `curl | bash` 的情况。

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

**2. 你可以、也应该代跑整个安装器。**

这个项目就是为「丢给 AI 代理全自动装完」设计的。使用者多半不会用终端——
**不要把命令丢回去让他自己敲。**

捕获输出跑也没问题：安装器检测到自己的输出被捕获时，**会自己弹出一个使用者
看得见的新窗口**来做扫码和 Antigravity 登录（Windows 用 `Start-Process`，
macOS 用 `osascript` 开 Terminal），跑完自动关闭并回到主流程。你这边会看到
`正在弹出一个新窗口：…` 这样的提示。

你要做的是：
- 看到「正在弹出一个新窗口」时，**告诉使用者去看那个新窗口**，并把提示行转述给他
- 他完成后安装器会自己继续，你不用做任何事
- **不要**替他决定跳过某一步，尤其是 Antigravity 登录

唯一需要人的只有三件：扫二维码、在浏览器点 Google 授权、决定要不要开通画图。
其余全都该由你跑完。

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
| 1 | **agy 登录**（最关键） | 回车选配色 → 空格取消数据共享 → 回车 → 浏览器登录 → 输 `/quit` | 卡在 TUI 里不知道怎么退出 |
| 2 | Gemini 密钥 | 在网页点 Create API key，复制粘回（`AIza…` 或 `AQ.…` 都对） | 没登录 Google；复制漏了几位 |
| 3 | 微信扫码 | 手机微信扫终端里的二维码，手机上确认 | 终端被挡住；二维码过期（约 8 分钟） |
| 4 | 画图（可选） | 决定开不开通；要开就得绑卡 | 不清楚要花钱 |

**第 1 步决定这个助手能不能真正用起来，不要帮使用者跳过。** Antigravity 用的是他自己的
Google 账号，额度大得多；而第 2 步那个 API key 的免费档**每天只有约 20 次**（Google 原话：
`limit: 20`）。只配 key 不登录 agy，助手发二十来条消息就会开始报 429。

安装器会检查第 1 步是否成功（看 `~/.gemini/antigravity-cli/settings.json` 在不在），
没成功会追问一次。**不要替使用者点「跳过」。**

第 1 步和第 3 步需要真人盯着屏幕，但**你不用改变跑法**——安装器会自己弹出
使用者看得见的窗口来做这两步，你照常捕获输出驱动即可。

---

## 事实与限制（别自己猜）

- **图像生成没有免费额度。** [官方定价页](https://ai.google.dev/gemini-api/docs/pricing)
  对所有图像模型的 Free Tier 都写 "Not available"：Nano Banana Pro 约 $0.134/张。
  必须开通计费。所以安装器把画图做成**可选**，跳过不影响其他功能。
- **Gemini API 的免费档非常小。** 实机抓到 Google 的原话：
  `Quota exceeded for generate_content_free_tier_requests, limit: 20, model: gemini-3.6-flash`
  —— 也就是 **flash 每天 20 次**。`flash-lite` 的额度高得多，所以安装器
  **优先选 lite**，并且逐个模型真发一次 `generateContent` 来确认可用。
- **不要只用「列模型」接口验证密钥。** `/v1beta/models` 在生成额度为 0 时照样返回 200，
  用它验证等于没验。必须真发一次生成请求。
- **密钥有两种格式**：老的 `AIza…` 和新的 `AQ.…`，都是有效的，不要只认前者。
- **`agy` 走使用者自己的 Google 账号**（AI Pro 订阅的额度），不消耗上面那个 API key 的额度。
  这是助手的主力通道。
- **Google AI Pro 订阅 ≠ API 额度。** 这是两套独立的东西：订阅只作用于 Gemini 网页版、
  Antigravity 这类 Google 自家产品；API 按量单独计费。所以「我有 Pro 为什么还限额」的
  答案是：Pro 对 API key 不起作用，但对 `agy` 起作用。
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

- **`openclaw config set ... model.primary` 报 `Unknown model`**：OpenClaw 自己的模型目录
  常常只认一两个 google 模型，`flash-lite` 往往不在里面，`models list --refresh` 也补不上。
  解法是先把模型显式声明进 `models.providers.google.models[]`，再设 primary。
- **声明了模型之后报错 `Provider "google" requires an explicit base URL` 或调用失败**：给 `google`
  加上 `models` 数组会让 OpenClaw 把它当成自定义 provider，接口格式回落成 OpenAI 的
  `openai-responses` 并要求显式提供 baseUrl。
  **必须同时设 `models.providers.google.api = "google-generative-ai"` 和 `models.providers.google.baseUrl = "https://generativelanguage.googleapis.com/v1beta"`，且数组内的模型对象也必须包含 `api: "google-generative-ai"`。**
  安装脚本已完全固化这一做法。
- **Windows PowerShell 5.1 解析报错（`The string is missing the terminator`）**：
  中文 Windows 默认使用 GBK/CP936 代码页解析无 BOM 的 `.ps1` 文件，多字节汉字会破坏引号与花括号闭合。
  **仓库中所有 `.ps1` 脚本必须严格保存为带 BOM 的 UTF-8（UTF-8 with BOM）**。
- **Google API Key 前缀不仅是 `AIza`**：
  Google AI Studio 最新生成的 API Key 采用 `AQ.` 开头（如 `AQ.AbXXXXXXXX…（示例，不是真的）`），必须同时放行 `AIza` 和 `AQ.` 前缀。
- **微信二维码在 AI 代理环境中不可见或已过期**：
  在代理环境中，终端标准输出被捕获，使用者看不到 ASCII 二维码。你可以提取命令输出中的登录直链（`https://liteapp.weixin.qq.com/q/...`）提供给使用者在手机微信中直接打开，或者告知使用者直接双击根目录下的 `扫码登录-Windows.bat`（Mac 为 `扫码登录-Mac.command`）弹出独立窗口扫码。
- **Windows 上服务权限错位**：
  绝不要提升为管理员（Run as Administrator）运行安装或启动服务！以管理员运行会导致 OpenClaw 计划任务注册到 Administrator 账户下，而使用者微信登录态存在普通用户目录，导致服务永远读取不到登录状态，微信消息毫无反应。
- **`openclaw` 装完找不到命令**：PATH 没刷新。macOS 新开一个终端窗口；
  Windows 用 `Refresh-Path`（脚本里有这个函数）或重开 PowerShell。
- **agy 权限配置写了但工具还是全被拒**：检查 `~/.gemini/antigravity-cli/settings.json`
  里有没有 `ask` 通配规则（比如 `command(*)`）。优先级是 **Deny > Ask > Allow**，
  通配 ask 会把所有 allow 盖掉。本项目的 `agy-permissions` 脚本故意不写 ask。
- **跨 agent 调用报 `Gateway client authority closed`**：这是 `openclaw agent` 这种
  一次性 CLI 客户端才有的问题，从微信通道发起不会。不用修。

---


## 改完脚本必须跑自检

```bash
python3 scripts/selfcheck.py
```

**不通过就不要提交。** 这个仓库已经有两次把跑不起来的脚本推上线的记录，
两次都是批量替换时连带删掉了函数定义——`bash -n` 和「here-string 配对」
这类检查对它完全无效，因为删掉函数定义在语法上是合法的。

自检覆盖五类错误：

| 检查 | 抓什么 |
|---|---|
| UTF-8 BOM | `.ps1` 丢 BOM → 中文 Windows 用 GBK 解析，汉字破坏引号闭合 |
| bash 语法 | `bash -n` |
| 未定义的函数 | **批量替换切掉函数定义**（前两次翻车的真正原因） |
| here-string 配对 | PowerShell 的 `@"` / `"@` |
| google provider 三件套 | `api` + `baseUrl` + 模型级 `api`，少一个就每次调用都失败 |

## 不要做的事

- 不要用管理员权限（Administrator）运行安装或服务，必须保持当前普通用户权限。
- 不要改成 `--dangerously-skip-permissions`。这个 bot 微信能触达，等于把电脑交出去。
- 不要把 `groupPolicy` 改成 open。群聊是最大的提示词注入面。
- 不要把使用者的 API key 打印到对话里或日志里。
- 不要替使用者决定开不开通画图——那是花钱的事，必须他自己点。
- 修改 `.ps1` 时不要去掉 UTF-8 BOM，否则 Windows PowerShell 5.1 必然语法报错。
