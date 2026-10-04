# Chrome 浏览器控制

> **官方完整文档（chrome-devtools-mcp 工具参考）**：https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/main/docs/tool-reference.md

本机 Chrome 的控制分两种方式：

| 方式 | 谁执行 | 能力 | 适用 |
|------|--------|------|------|
| **① Chrome DevTools MCP（推荐）** | opencode 大脑直接调用 MCP 工具 | 读页面、精确点击/填表/取文本 | 绝大部分网页任务 |
| ② Lua + xdotool（兜底） | opencode 调 `operator/tools/browser.sh` | 只能开标签/搜索/截图，**读不到页面** | 粗动作 |

> 规则：**禁止用 OCR 识别网页**。要读网页内容一律走 MCP。

---

## 方式一：Chrome DevTools MCP（推荐）

### 配置
`operator/opencode.json`：
```json
{
  "mcp": {
    "chrome-devtools": {
      "type": "local",
      "command": ["npx", "-y", "chrome-devtools-mcp@latest", "--autoConnect", "--channel", "stable", "--no-usage-statistics"],
      "enabled": true
    }
  }
}
```

### 前置（一次性，Chrome 144+）
在你**日常已登录**的 Chrome 里打开：
```
chrome://inspect/#remote-debugging
```
打开「允许远程调试」。`--autoConnect` 会连这个已登录实例（保留 cookie/登录态），不再单起隔离小号。
（Chrome 重启后可能要重新放行。）

### 大脑可用的 MCP 工具（名如 `chrome-devtools_*`）

**默认启用（约 30 个）**：

| 类别 | 工具 | 用途 |
|------|------|------|
| 输入 (10) | `click` `fill` `fill_form` `hover` `drag` `press_key` `type_text` `upload_file` `handle_dialog` `click_at`\* | 点击/填表/拖拽/按键/上传/弹窗 |
| 导航 (6) | `new_page` `navigate_page` `list_pages` `select_page` `close_page` `wait_for` | 开关/切换页面、跳转、等文本出现 |
| 调试·读取 (9) | `take_snapshot` `take_screenshot` `evaluate_script` `list_console_messages` `get_console_message` `get_css_styles` `lighthouse_audit` `screencast_start`/`screencast_stop`\* | 读 a11y 树(拿元素 uid)、截图、跑 JS、console/CSS、Lighthouse |
| 网络 (2) | `list_network_requests` `get_network_request` | 看请求/响应头（含 Cookie） |
| 性能 (3) | `performance_start_trace` `performance_stop_trace` `performance_analyze_insight` | 性能追踪、Core Web Vitals |
| 设备模拟 (2) | `emulate` `resize_page` | 深色模式/UA/视口/网络限速/定位 |

**需加 flag 才启用**：

- 内存 (14)：`take_heapsnapshot` 及 `*_heapsnapshot_*` —— `--memoryDebugging`
- 扩展 (5)：`install_extension` / `list_extensions` / `reload_extension` / `trigger_extension_action` / `uninstall_extension` —— `--categoryExtensions`
- WebMCP / 第三方工具 / PWA —— `--categoryExperimentalWebmcp` / `--categoryExperimentalThirdParty` / `--categoryPwa`

\* `click_at`（按坐标点击）需 `--experimentalVision`；录屏需 `--experimentalScreencast`。

**常用启动参数**：`--slim`（只露导航/脚本/截图 3 个工具）、`--headless`（无界面）、`--autoConnect`（连已登录 Chrome）、`--channel stable`。

**关键用法**：读网页优先 `take_snapshot`（拿元素 uid + 文本）→ 据此 `click`/`fill`；抓数据用 `evaluate_script`。**禁止 OCR 网页。**

启动时 opencode 会加载该 MCP；`opencode mcp list` 应显示 `✓ chrome-devtools connected`。

**官方文档**：
- 工具参考（完整参数）：https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/main/docs/tool-reference.md
- 仓库 / README：https://github.com/ChromeDevTools/chrome-devtools-mcp

---

## 方式二：Lua + xdotool（兜底粗动作）

纯 Lua 模块 `wechat_ocr.chrome`，经 xdotool 操作**现有** Chrome，不启动新进程。
opencode 侧通过白名单脚本 `operator/tools/browser.sh` 调用它。

```lua
local chrome = require("wechat_ocr.chrome")
chrome.new_tab()              -- Ctrl+T 新空白标签
chrome.open("url")            -- 新标签打开网址
chrome.search("关键词")        -- Google 搜索
chrome.ai_search("问题")       -- Google AI 模式（地址栏→Tab→回车）
chrome.screenshot(path)       -- 截图
```

对应 opencode 工具（`operator/tools/browser.sh`）：
```bash
tools/browser.sh new_tab
tools/browser.sh open <url>
tools/browser.sh search <关键词>
tools/browser.sh ai_search <问题>
tools/browser.sh screenshot [输出路径]
```
依赖：`xdotool`、`xclip`、`ImageMagick`。

---

## opencode 是怎么调起来的

```
语音 [语音输入] / 微信 [微信输入]
      │  (voice/listen、wechat-ocr/bridge 用 curl 转发到 opencode TUI)
      ▼
opencode 大脑（tmux 常驻 TUI，4097）
      │  读 operator/AGENTS.md 规则
      ├─ 浏览器 → 直接用 chrome-devtools MCP 工具
      └─ 本机动作 → 调 operator/tools/*.sh（白名单，如 browser.sh / screenshot.sh / say.sh / wechat_send.sh）
```
要点：**MCP 由 opencode 直接调用**；**sh 脚本也由 opencode 调用**（受 `operator/opencode.json` 白名单 + `guard.js` 约束）。

---

## 必须遵守的规则

1. **只用 MCP 读网页** — 网页交互/内容读取走 `chrome-devtools_*` 工具；**禁止 OCR 识别浏览器页面**。
2. **操作现有 Chrome** — 不启动新浏览器进程；用 `--autoConnect` 连已登录实例。
3. **`browser.sh` 只做粗动作** — 开标签/搜索/截图；不要靠它读页面。
4. **白名单** — opencode 侧只能调 `operator/tools/*.sh`，不得任意 shell。

---

*相关：`operator/AGENTS.md`（运行时契约）、`operator/tools/browser.sh`、`wechat-ocr/lua/wechat_ocr/chrome.lua`*
*文档版本: 2.1 · 更新日期: 2026-10-04*
