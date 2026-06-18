# Chrome 浏览器控制模块

## 简介

纯 Lua 实现的 Chrome 控制模块，操作现有 Chrome 浏览器（不打开新浏览器），通过 xdotool 模拟键盘快捷键。

## 安装

不需要安装，模块已内置：

```lua
local chrome = require("wechat_ocr.chrome")
```

依赖：`xdotool`、`xclip`、`ImageMagick`（均已安装）

## API

### `chrome.new_tab()`

打开新空白标签页（Ctrl+T），显示 Chrome 默认新标签页（含 Google 搜索框）。

```lua
chrome.new_tab()
```

### `chrome.open(url)`

新标签打开指定网址。

```lua
chrome.open("https://www.google.com")
```

### `chrome.search(keyword)`

新标签打开 Google 搜索。

```lua
chrome.search("chrome 有什么好玩的玩法")
```

### `chrome.ai_search(keyword)`

**Google AI 模式搜索** — 地址栏输入问题 → Tab → 回车，触发 Google AI 回答。

```lua
chrome.ai_search("chrome mcp 有什么好玩的玩法")
```

内部流程：`Ctrl+T` → 粘贴问题 → `Tab`（移到 AI 模式选项）→ `Return`

### `chrome.screenshot(path)`

截图当前标签页，保存到文件。

```lua
chrome.screenshot("/tmp/page.png")  -- 默认 /tmp/chrome_ss.png
```

## 原理

| 操作 | 方式 |
|------|------|
| 新标签 | `xdotool key ctrl+t` |
| 打开网址 | 剪贴板粘贴 + 回车 |
| 截图 | `import -window root -crop` |
| 窗口激活 | `xdotool windowactivate` |

不启动新浏览器，不依赖 MCP 守护进程，不需要 Node.js。

---

*文件位置: `/usr/local/lualib/wechat_ocr/chrome.lua`*
*文档版本: 1.0*
*更新日期: 2026-06-18*
