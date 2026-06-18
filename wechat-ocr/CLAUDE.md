# Chrome 浏览器控制规则（必须遵守）

1. **用 Lua** — 通过 `require("wechat_ocr.chrome")` 调用，不得使用 Node.js/其他语言
2. **不打开新浏览器** — 只能操作现有 Chrome 窗口（`xdotool search --name Google.Chrome`），不得启动新 Chrome 进程
3. **新开空白标签** — 用 `chrome.new_tab()`（Ctrl+T），不要打开具体网址，除非用户明确要求

```lua
local chrome = require("wechat_ocr.chrome")
chrome.new_tab()          -- ✅ 新开空白标签
chrome.open("网址")        -- ✅ 新标签打开网址
chrome.search("关键词")    -- ✅ 新标签 Google 搜索
chrome.screenshot()       -- ✅ 截图
```
