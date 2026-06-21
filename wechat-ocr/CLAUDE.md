# Chrome 浏览器控制规则（必须遵守）

1. **用 Lua** — 通过 `require("wechat_ocr.chrome")` 调用，不得使用 Node.js/其他语言
2. **不打开新浏览器** — 只能操作现有 Chrome 窗口（`xdotool search --name Google.Chrome`），不得启动新 Chrome 进程
3. **新开空白标签** — 用 `chrome.new_tab()`（Ctrl+T），不要打开具体网址，除非用户明确要求
4. **禁止 OCR 识别浏览器网页** — 不得使用 PaddleOCR 或任何 OCR 方式识别浏览器页面内容，浏览器页面交互必须通过 MCP 或 xdotool 完成

```lua
local chrome = require("wechat_ocr.chrome")
chrome.new_tab()              -- ✅ 新开空白标签
chrome.open("网址")            -- ✅ 新标签打开网址
chrome.search("关键词")        -- ✅ 新标签 Google 搜索
chrome.ai_search("问题")       -- ✅ AI 模式搜索（地址栏→Tab→回车）
chrome.screenshot()           -- ✅ 截图
```

## AI 搜索（Google AI 模式）

**地址栏输入问题 → Tab → 回车** 触发 Google AI 回答：

```lua
chrome.ai_search("chrome mcp 有什么好玩的玩法")
```

内部流程：`Ctrl+T` → 粘贴问题 → `Tab`（移到 AI 模式选项）→ `Return`（回车）

---

*文档版本: 1.1*
*更新日期: 2026-06-21*
