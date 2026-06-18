# Chrome 浏览器控制模块

## 简介

纯 Lua 实现的 Chrome 控制模块，通过 `google-chrome` 命令行 + `xdotool` + `import` 操作浏览器。不需要 MCP 守护进程、不需要 Node.js、不需要第三方依赖。

## 架构

```
┌─────────────────────────────────────────────────────┐
│                    上层应用                          │
│  wechat_robot.lua (微信监控)  /  其他 Lua 脚本       │
└────────────────────┬────────────────────────────────┘
                     │ require("wechat_ocr.chrome")
┌────────────────────▼────────────────────────────────┐
│              chrome.lua (浏览器控制模块)              │
│                                                     │
│  M.open(url)     → google-chrome 命令行开新标签页    │
│  M.screenshot()  → import 截图（同微信OCR方式）      │
│  M.search(kw)    → Google 搜索                      │
└────────────────────┬────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────┐
│                 系统命令                              │
│  google-chrome   浏览器控制                          │
│  xdotool         窗口/鼠标/键盘操作                   │
│  import          ImageMagick 截图                     │
│  xclip           剪贴板操作                           │
└─────────────────────────────────────────────────────┘
```

## 安装

不需要安装，模块已内置在 `wechat_ocr` 包中：

```lua
local chrome = require("wechat_ocr.chrome")
```

依赖：`google-chrome`、`xdotool`、`ImageMagick`（均已安装）

## 使用方式

### 打开网页（新标签页）

```lua
chrome.open("https://www.google.com")
```

### Google 搜索

```lua
chrome.search("世界杯今日比赛汇总")
-- 等效于 chrome.open("https://www.google.com/search?q=世界杯今日比赛汇总")
```

### 截图

```lua
local path = chrome.screenshot("/tmp/page.png")
-- 不传路径默认保存到 /tmp/chrome_ss.png
```

## 与 MCP 的关系

| 方式 | 适用场景 | 优点 | 缺点 |
|------|---------|------|------|
| `chrome.lua`（xdotool） | Lua 脚本、微信监控 | 纯 Lua，无依赖，无需守护进程 | 只能做基本操作 |
| Chrome DevTools MCP | opencode AI 代理 | 完整 DevTools 能力 | 需要 opencode 集成 |

两者互补：Lua 脚本用 `chrome.lua` 做简单操作，opencode 内用 MCP 做高级调试。

---

*文件位置: `/usr/local/lualib/wechat_ocr/chrome.lua`*
*文档版本: 1.0*
*更新日期: 2026-06-18*
