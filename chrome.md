# Chrome 浏览器控制

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
| 工具 | 用途 |
|------|------|
| `new_page` / `close_page` | 新开/关闭页面 |
| `navigate_page` | 跳转网址 |
| `take_snapshot` | 取无障碍树快照（读页面结构，给元素定位） |
| `click` / `fill` / `hover` | 按元素点击/填写/悬停 |
| `evaluate_script` | 在页面执行 JS（如取 `document.title`、抓数据） |
| `take_screenshot` | 截图 |
| `wait_for` / `list_network_requests` 等 | 等待、网络观察 |

启动时 opencode 会加载该 MCP；`opencode mcp list` 应显示 `✓ chrome-devtools connected`。

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
*文档版本: 2.0 · 更新日期: 2026-10-04*
