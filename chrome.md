# Chrome 浏览器控制模块

## 简介

纯 Lua 实现的 Chrome 控制模块，操作现有 Chrome 浏览器（不打开新浏览器），通过 xdotool 模拟键盘快捷键。

在微信机器人场景中，Chrome 主要用于：
- 收到微信指令后触发 Google AI 搜索；
- 获取网页信息后再把结果发回微信。

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

## 在微信机器人中的典型用法

```lua
local robot = require("wechat_robot")
local chrome = require("wechat_ocr.chrome")

robot.init()
robot.monitor({
    interval_ms = 3000,
    on_message = function(text)
        -- 以 @ai 开头的消息触发 AI 搜索
        if text:match("^@ai") then
            local question = text:sub(4):match("^%s*(.*)")
            chrome.ai_search(question)

            -- 等待 AI 回答
            local ffi = require("ffi")
            ffi.cdef[[void usleep(unsigned int);]]
            ffi.C.usleep(4000000)

            -- 复制页面内容
            os.execute("xdotool key ctrl+a ctrl+c")
            ffi.C.usleep(500000)

            -- 读取剪贴板
            local pipe = io.popen("xclip -selection clipboard -o")
            local answer = pipe:read("*a"); pipe:close()

            -- 把结果发回微信
            robot.send(answer:sub(1, 1000))
        end
    end
})
```

---

## 必须遵守的规则

1. **用 Lua** — 通过 `require("wechat_ocr.chrome")` 调用，不得使用 Node.js/其他语言
2. **不打开新浏览器** — 只能操作现有 Chrome 窗口，不得启动新 Chrome 进程
3. **新开空白标签** — 用 `chrome.new_tab()`（Ctrl+T），不要打开具体网址，除非用户明确要求
4. **禁止 OCR 识别浏览器网页** — 不得使用 PaddleOCR 或任何 OCR 方式识别浏览器页面内容，浏览器页面交互必须通过 MCP 或 xdotool 完成

```lua
local chrome = require("wechat_ocr.chrome")
chrome.new_tab()          -- ✅ 新开空白标签
chrome.open("网址")        -- ✅ 新标签打开网址
chrome.search("关键词")    -- ✅ 新标签 Google 搜索
chrome.ai_search("问题")   -- ✅ AI 模式搜索
chrome.screenshot()       -- ✅ 截图
```

---

*文件位置: `/usr/local/lualib/wechat_ocr/chrome.lua`*
*文档版本: 1.1*
*更新日期: 2026-06-21*
