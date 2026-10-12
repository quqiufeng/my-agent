# 项目能力清单（Capabilities）— 供大脑上下文

> 大脑做决策前先看这里：**有哪些现成能力可以满足需求**；没有的才用 `tools/dev.sh` 开发（只做 Chrome 扩展）。
> 与 `TOOLS.md`（白名单工具表）配合使用。

## 一、网页 / 浏览器
- **专用 Chrome（固定端口，免授权）**：`tools/chrome_debug.sh`（用 Chrome 前必须）
- **CDP/DOM 精准控制**：`ak.cdp`（Lua）或大脑的 `chrome-devtools` MCP
  `title/url/eval/text/html/query/click/goto/cookies/gemini`
- **谷歌搜索/新闻（结构化）**：`tools/google_search.sh "<关键词>" [--news]`
- **Google AI（Gemini）问答**：`tools/gemini.sh "<问题>"[--display]`
  Lua：`ak.cdp.gemini(q)` / `ak.cdp.ask(q)`
- **GitHub 热门**：`tools/git_trending.sh [--lang lua]`
- **登录态抓取（免浏览器）**：`tools/cookie.sh`（取 cookie 落 `.env`）+ `tools/fetch.sh <url> --cookie KEY`
- **浏览器扩展自我开发**：`tools/dev.sh ext new|load|list`（能力只通过扩展扩展）

## 二、本机界面自动化（agentkit，LuaJIT+FFI）
```lua
package.path="/opt/my-agent/?.lua;/opt/my-agent/?/init.lua;"..package.path
local ak=require("agentkit")
ak.x11.window(title); win:ocr()/find_text/click_text/ocr_bands   -- 窗口+OCR+点击
ak.map("wechat")/("chrome")/("google"/"gemini"/"github")         -- 控件映射
ak.app("wordcard"/"wechat"/"chrome"/"gemini"/"google"/"github")  -- 应用适配器
ak.voice.tts/asr/record                                          -- 语音
ak.batch.run(app,kind,items)   ak.record(app)                    -- 批量/录制
```
- 映射文件：`agentkit/maps/*.lua`；多分辨率：`agentkit/tools/scale_maps.lua`

## 三、出图 / 排版（Kami）
- `operator/report/render.sh in.html out.png|.pdf`（headless Chrome）
- 样式：`operator/report/kami.css`；规范：`operator/report/TYPOGRAPHY.md`
- 现成生成器：`report/{github_trending,google_report,gemini_report}.lua`、`daily-report.html`

## 四、出入口
- **微信**：`tools/wechat_send.sh`（文本）、`tools/wechat_send_file.sh`（图/文件）
- **微博抓图**：`tools/weibo_imgs.sh`（搜索）、`tools/weibo_album.sh`（相册大图）
- **语音**：`ak.voice` 或 `voice/voice.sh say|listen`（SenseVoice / sherpa+Kokoro）

## 五、内容管道 / 系统 / 媒体（tools/*.sh、tools/*.py）
- 解析/翻译/查词/OCR/TTS：`tools/*.py`（ECDICT/LLM/PP-OCR）；电子书：`tools/ebook_extract.py`
- 屏幕/图像/视频：`screenshot.sh image.sh img_video.sh video_dub.sh`
- 行情/大屏：`stock.sh quote_web.sh dash.sh`；音乐/电视：`music.sh tv.sh`
- 手机：`phone.sh`；语音/音频：`say.sh voices.sh`
- 其他：`now.sh find_file.sh note.sh open_app.sh remote.sh ...`（见 TOOLS.md 全表）

## 六、自我扩展（闭环）
- `tools/dev.sh info`（学规范）→ `ext new <name>`（生成 Chrome 扩展，自动 git commit）→ 填 content/background → `ext load <name>` 生效 → `push` 同步。
- 扩展在 `operator/extensions/`（仓库内，可 `git revert` 回滚）。
- **规则：新能力只做浏览器扩展**（沙箱，按 manifest 授权；不给机器任意权限）。

## 关键环境
- 显示：会话内 `DISPLAY=:0` + 从 `pcmanfm-qt` 派生 `XAUTHORITY`；Docker/无头需 Xvfb。
- 专用 Chrome profile：`~/.chrome-debug-profile`（`chrome_debug.sh` 每次同步登录态）。
- 密钥/凭据：`~/.env`（如 `WEIBO_COOKIE`、`FUYAO_API_KEY`、`WEBDAV_*`）。
