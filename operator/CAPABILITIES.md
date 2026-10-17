# 项目能力清单（Capabilities）— 供大脑上下文

> 大脑决策前先看这里：**有哪些现成能力**；没有的才用 `tools/dev.sh` 开发
> （**新能力=走专用 Chrome（免授权登录）+ CDP/DOM 的网页工具**，能力只来自网页，安全）。
> 与 `TOOLS.md`（白名单工具表）配合使用。

## 一、网页 / 浏览器
- **专用 Chrome（固定端口 9222、免授权、带登录）**：`tools/chrome_debug.sh`（用 Chrome 前必须）
- **CDP/DOM 精准控制**：`ak.cdp`（Lua）或大脑的 `chrome-devtools` MCP
  `title/url/eval/text/html/query/click/goto/cookies/gemini`
- **谷歌搜索/新闻（结构化）**：`tools/google_search.sh "<关键词>" [--news]`
- **Google AI（Gemini）问答**：`tools/gemini.sh "<问题>"[--display]`；Lua：`ak.cdp.gemini/ask`
- **GitHub 热门**：`tools/git_trending.sh [--lang lua]`
- **登录态抓取（免浏览器）**：`tools/cookie.sh`（取 cookie 落 `.env`）+ `tools/fetch.sh <url> --cookie KEY`
- **自我开发新能力**：`tools/dev.sh new <name>`（生成走专用 Chrome + `ak.cdp` 的网页工具）

## 二、本机界面自动化（agentkit，LuaJIT+FFI）
```lua
package.path="/opt/my-agent/?.lua;/opt/my-agent/?/init.lua;"..package.path
local ak=require("agentkit")
ak.x11.window(title); win:ocr()/find_text/click_text/ocr_bands   -- 窗口+OCR+点击
ak.map("wechat"/"chrome"/"google"/"gemini"/"github")             -- 控件映射
ak.app("wordcard"/"wechat"/"chrome"/"gemini"/"google"/"github")  -- 应用适配器
ak.voice.tts/asr/record    ak.batch.run(app,kind,items)   ak.record(app)  -- 语音/批量/录制
```
- 映射：`agentkit/maps/*.lua`；多分辨率：`agentkit/tools/scale_maps.lua`

## 三、出图 / 排版（Kami）
- `operator/report/render.sh in.html out.png|.pdf`
- 样式 `operator/report/kami.css`；规范 `operator/report/TYPOGRAPHY.md`
- 现成生成器：`report/{github_trending,google_report,gemini_report}.lua`、`daily-report.html`

## 四、出入口
- **微信**：`tools/wechat_send.sh`（文本）、`tools/wechat_send_file.sh`（图/文件）
- **微博抓图**：`tools/weibo_imgs.sh`（搜索）、`tools/weibo_album.sh`（相册大图）
- **语音**：`ak.voice` 或 `voice/voice.sh say|listen`（SenseVoice / sherpa+Kokoro）

## 五、内容管道 / 系统 / 媒体
- 解析/翻译/查词/OCR/TTS：`tools/*.py`；电子书：`tools/ebook_extract.py`
- 屏幕/图像/视频：`screenshot.sh image.sh img_video.sh video_dub.sh`
- 行情/大屏：`stock.sh quote_web.sh dash.sh`；音乐/电视：`music.sh tv.sh`
- 手机：`phone.sh`；音频：`say.sh voices.sh`；其他见 `TOOLS.md` 全表
- **电纸书（Kindle DXG）**：`tools/ebook.sh state|say|shot|dump|speak|books|test`
  自研 LVGL 阅读器（书架/阅读/目录/进度/三档字号）；**文本指令**（`/tmp/ui_say`，语音/无障碍）、
  **截图可被 AI 直接读**做视觉验证；闭环测试/工具链见 `agentkit/kindle/boot/test/README.md`

## 六、自我扩展（网页能力，安全）
- 目录/机制：新能力 = 一个 `tools/<name>.sh`，内部走**专用 Chrome（免授权登录）+ `ak.cdp` DOM 操作**；**能力只来自网页**，不碰本机任意文件/进程/网络权限。
- 闭环：`tools/dev.sh info`（学规范）→ `new <name>`（生成网页工具骨架，自动 git commit）→ 填逻辑 → `commit`（可回滚）→ `index` + `restart` 生效 → 可选 `push`。
- **不做浏览器扩展**，也不写执行任意系统命令的脚本。
- 护栏：改动自动 `git commit`（`git revert` 可回滚）；`push` 同步远端。

## 七、全自动化开发流程（无需人工干预）
> 详见 `automation.md`（Fully-Automated Mode）。闭环：
> **设计 → 构建 → 会话内运行 → 截图识别 → 驱动(xdotool/CDP) → 校验 → 迭代 → 提交**，全程无人工。
- **运行**：一律在**图形会话内**起（`DISPLAY=:0` + 从 `pcmanfm-qt` 派生 `XAUTHORITY`）；GUI 勿用 systemd（缺 X/GL 起不了窗）。
- **截图识别**：`agentkit/bin/shot.sh`（或 `tools/screenshot.sh`，GL 窗口 root 抓取+裁剪）→ `Read` 读图；`ak.ocr`（PP-OCR）/`win:ocr()`/`win:ocr_bands()`；模板匹配 `ak_match`、图像差分 `ak_diff`。
- **驱动**：**xdotool**（`ak.x11` / `ak.map` 控件映射）、**CDP**（`ak.cdp`）、XTest（libagentkit）。
- **自动化测试/校验**：操作后**自检**——OCR 文本是否变化 / 图像差分阈值 / DOM 断言；失败**重试**。
- **迭代**：定位差异 → 改代码 → 重建/运行 → 复验（提交前过 `bash -n` 等静态检查）。
- **自我扩展**：新能力=网页工具（专用 Chrome + CDP/DOM），改动**自动 git commit**（可回滚）。

## 关键环境
- 显示：会话内 `DISPLAY=:0` + 从 `pcmanfm-qt` 派生 `XAUTHORITY`；无头需 Xvfb。
- 专用 Chrome profile：`~/.chrome-debug-profile`（`chrome_debug.sh` 每次同步登录态）。
- 密钥/凭据：`~/.env`（`WEIBO_COOKIE`、`FUYAO_API_KEY`、`WEBDAV_*` 等）。
