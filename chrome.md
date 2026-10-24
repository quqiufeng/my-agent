# Chrome 浏览器控制

> **官方完整文档（chrome-devtools-mcp 工具参考）**：https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/main/docs/tool-reference.md

**关键约定：凡是要用 Chrome 的功能，一律先启动「专用 Chrome 实例」（固定调试端口），MCP 通过 `--browser-url` 连它 —— 免授权弹窗、保留登录。**

本机 Chrome 的控制分两种方式：

| 方式 | 谁执行 | 能力 | 适用 |
|------|--------|------|------|
| **① Chrome DevTools MCP（推荐）** | opencode 大脑直接调用 MCP 工具 | 读页面、精确点击/填表/取文本 | 绝大部分网页任务 |
| ② 粗动作 | 用 chrome-devtools MCP 新开标签/导航 | 读页面/交互仍走 MCP/DOM | 常规 |

> 规则：**禁止用 OCR 识别网页**。要读网页内容一律走 MCP。

---

## 方式一：Chrome DevTools MCP（推荐）

### 1) 启动专用 Chrome 实例（免授权的前提）

```bash
operator/tools/chrome_debug.sh            # 默认端口 9222（可传端口）
```

- 用**专用 profile** `~/.chrome-debug-profile`：首次/每次启动前从你的默认 profile **同步登录数据**（排除大缓存、端上模型），所以**登录态保留**；
- 以 `--remote-debugging-port=9222` 启动 → **经典调试端口，连多少客户端都不弹授权**；
- 与日常 profile **隔离**（Chrome 强制要求非默认目录）。

### 2) MCP 配置（`operator/opencode.json`）

```json
{
  "mcp": {
    "chrome-devtools": {
      "type": "local",
      "command": ["npx", "-y", "chrome-devtools-mcp@latest", "--browser-url=http://127.0.0.1:9222", "--no-usage-statistics"],
      "enabled": true
    }
  }
}
```

- `--browser-url` 挂到上面那个**固定端口实例**（长连接）→ **不再每次弹授权**；
- 改配置后需**重启大脑**（opencode 不热重载）：`operator/start.sh`。

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

**关键用法**：读网页优先 `take_snapshot`（拿元素 uid + 文本）→ 据此 `click`/`fill`；抓数据用 `evaluate_script`。**禁止 OCR 网页。**

启动时 opencode 会加载该 MCP；`opencode mcp list` 应显示 `✓ chrome-devtools connected`。

**官方文档**：
- 工具参考（完整参数）：https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/main/docs/tool-reference.md
- 仓库 / README：https://github.com/ChromeDevTools/chrome-devtools-mcp

---

## 方式二：Lua + xdotool（兜底粗动作）

纯 Lua 模块 `wechat_ocr.chrome`，经 xdotool 操作**现有** Chrome，不启动新进程。
`browser.sh` 已移除；常规由 chrome-devtools MCP 操作，`wechat_ocr.chrome` 仅保留给旧测试。

```lua
local chrome = require("wechat_ocr.chrome")
chrome.new_tab()              -- Ctrl+T 新空白标签
chrome.open("url")            -- 新标签打开网址
chrome.search("关键词")        -- Google 搜索
chrome.ai_search("问题")       -- Google AI 模式（地址栏→Tab→回车）
chrome.screenshot(path)       -- 截图
```

常规操作直接用 chrome-devtools MCP：新开标签页、导航、点击/填写、截图。
依赖：`xdotool`、`xclip`、`ImageMagick`。

---

## opencode 是怎么调起来的

```
语音 [语音输入] / 微信 [微信输入]
      │  (voice/listen、wechat-ocr/bridge 用 curl 转发到 opencode TUI)
      ▼
opencode 大脑（tmux 常驻 TUI，4097）
      │  读 operator/AGENTS.md 规则
      ├─ 浏览器 → 直接用 chrome-devtools MCP 工具（连固定端口实例）
      └─ 本机动作 → 调 operator/tools/*.sh（白名单，如 screenshot.sh / say.sh / wechat_send.sh）
```

---

## 必须遵守的规则

1. **只用 MCP 读网页** — 网页交互/内容读取走 `chrome-devtools_*` 工具；**禁止 OCR 识别浏览器页面**。
2. **用 Chrome 前先启动专用实例** — `tools/chrome_debug.sh`（固定端口、免授权、带登录）；**不要让工具直连日常默认 Chrome**。
3. **不要用旧 browser.sh** — 已删除；统一走 chrome-devtools MCP。
4. **白名单** — opencode 侧只能调 `operator/tools/*.sh`，不得任意 shell。

---

## 附：为什么固定端口就不弹授权

- `chrome://inspect` 的 `--autoConnect`：暴露的是你**已登录的日常实例** → 出于安全，**每来一个客户端都要点“允许”**。
- `--remote-debugging-port`（本方案）：**启动即授权**（flag 就是 opt-in）＋**专用隔离 profile** ＋ **仅绑 127.0.0.1** → 无需每次点。

> 旧的「视觉点授权」方式已移除；统一用固定端口 + CDP。

---

*相关：`operator/AGENTS.md`（运行时契约）、`operator/tools/chrome_debug.sh`、`agentkit/tools/gemini.js`*
*文档版本: 3.0 · 更新日期: 2026-10-12*
