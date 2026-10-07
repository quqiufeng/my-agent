<!-- 自动生成 by operator/plugin.sh index —— 请勿手改；新增工具后重跑即可 -->
# 工具与技能（白名单）

**只能**调用下列 `operator/tools/*.sh`。除此之外的任何命令、文件读写、网络一律禁止。
一条指令只调一个工具；禁止用 `&&`、`;`、`|`、重定向拼接（会被 guard 拦截）。

| 工具 | 用途 | 用法 |
|------|------|------|
| `tools/browser.sh` | 操作本机 Chrome（不新开浏览器） | `browser.sh new_tab` |
| `tools/dash.sh` | 股票大屏（点阵风·暗色：指数环+自选股+小K线） | `tools/dash.sh [--to 会话] [--show]` |
| `tools/english.sh` | 英语口语陪练（麦克风识别英文，回复用英文音色朗读） | `tools/english.sh start|stop|status` |
| `tools/find_file.sh` | 按文件名关键词搜索本机文件 + WebDAV，返回匹配（本地路径 或 可下载 URL） | `find_file.sh <关键词> [数量=15]` |
| `tools/gemini_out.sh` | 把（Gemini 等）获取到的结果按目标转发 | `tools/gemini_out.sh` |
| `tools/image.sh` | 生成图片并发送到微信（默认文件传输助手） | `tools/image.sh` |
| `tools/music.sh` | WebDAV 无损音乐：搜索 / 随机 / 播放 / 停止（VLC → USB 音响） | `tools/music.sh` |
| `tools/note.sh` | 备忘 / 待办（存 ~/.myagent_notes，纯文本） | `tools/note.sh` |
| `tools/now.sh` | 返回当前日期与时间 | `tools/now.sh` |
| `tools/open_app.sh` | 打开白名单内的本机应用 | `open_app.sh <chrome|terminal|files|editor|wechat>` |
| `tools/phone.sh` | 控制连接的安卓手机：截屏、点击、滑动、按键、输入(含中文)、打开应用、列出/安装应用 | `tools/phone.sh status                        # 查看是否已连接` |
| `tools/photo.sh` | USB 摄像头拍照并发微信（默认文件传输助手） | `tools/photo.sh` |
| `tools/progress.sh` | 查看开发进度：点击 qterminal，逐个 tab 截图 opencode，合并后发微信 | `progress.sh [--to 会话]` |
| `tools/quote_web.sh` | 看行情（浏览器打开搜狐行情页并全屏截图发微信） | `tools/quote_web.sh [名称或代码] [--to 会话]` |
| `tools/remote.sh` | 管理本机/远程的 tmux + opencode 集群 | `tools/remote.sh` |
| `tools/say.sh` | USB 音响播放语音（文本转语音） | `tools/say.sh` |
| `tools/screenshot.sh` | 截屏（默认全屏），返回图片路径 | `screenshot.sh [可选输出路径]` |
| `tools/send_images.sh` | 下载图片（小图自动换大图）：保存目录并报张数，或发微信 | `tools/send_images.sh [--save 目录] [--to 会话] [--each] [--limit N] <图片URL...>   （URL 也可从 stdin 每行一个）` |
| `tools/stock.sh` | 股票查询：行情快照 / 历史K线 / 估值 / 财务指标（同花顺数据源） | `tools/stock.sh <名称或代码> | kline <名称或代码> [天数] | value <名称或代码> | fin <名称或代码> [报告期如2024-4] | list` |
| `tools/tv.sh` | DAV 美剧/电影：列出 / 播放 / 下一集 / 停止（VLC 播放，默认本机屏幕） | `tools/tv.sh` |
| `tools/vocab.sh` | 记单词（弹卡片→读单词判发音→✓下一个 / ✗弹释义卡帮助记忆） | `tools/vocab.sh start|stop|status | add <英文> <中文> | list` |
| `tools/wechat_send_file.sh` | 发送文件/图片到微信 | `wechat_send_file.sh <本地路径|http(s)://URL> [--to 联系人]` |
| `tools/wechat_send.sh` | 发送微信文本 | `wechat_send.sh "内容"                  # 默认发到当前会话（文件传输助手）` |
| `tools/wechat_shot.sh` | 截屏发微信（微信 Alt+A 截当前屏幕 → 剪贴板 → 粘贴发送到指定会话/文件传输助手） | `tools/wechat_shot.sh            # 截图发到文件传输助手` |
| `tools/weibo_imgs.sh` | 下载微博图（打开微博搜索，抓九宫格图并小图换大图，存到 ~ 报张数） | `tools/weibo_imgs.sh <明星/关键词> [页数 | A-B | all，默认 20] [--save 目录] [--each] [--limit N] [--to 会话] [--refresh-cookie]` |
| `tools/weibo.sh` | 微博搜索（浏览器打开微博搜索页并全屏截图发微信） | `tools/weibo.sh <关键词> [--to 会话]` |

## 通用规则

1. 禁止读写项目源码、改系统配置、装/删软件、关机重启。
2. 需要给非默认会话发消息时，先确认对方身份，避免误发。
3. 不认识的请求 → 回复“这个我暂时不支持”，不要尝试绕过白名单。
4. **浏览器只用于网页任务**：读网页/交互走 chrome-devtools MCP，禁止用 OCR 识别网页；纯信息类（时间、算数、常识）不要动用浏览器。

## 各工具使用规则

1. **问时间/日期**（“现在几点 / 今天几号 / 星期几”）→ 用 `now.sh`，不要为此调浏览器或其它工具。
2. **截屏**：说“截个屏/截屏发我”→ `screenshot.sh`（返回路径），再用 `wechat_send_file.sh <路径> [--to 来源会话]` 发回。
3. **音乐**：说“放歌/放某某的歌/随机放一首”→ `play <歌手或歌名>`（没说放哪首就 `random`）；“下一首/换一首/切歌”→ `next`；“停/别放了”→ `stop`；“大声点/小声点”→ `volup`/`voldown`。拿不准先 `search <关键词>` 看匹配再 play。
4. **画图/生成图片**：说“画一张…/生成图片…/来个…的图”→ `image.sh "提示词"`（默认 1440x1920 竖版）。出图要几分钟，完成后脚本自动把图发到微信，你只需简短确认。GPU 忙时会被拒绝，稍后再试。
5. **发文件给我**：说“把 xxx 文件发我 / 找 xxx 文件 / 发我某首歌 / 找某部美剧”→ 先 `find_file.sh <关键词>`（本机 + WebDAV 都搜）。唯一匹配就直接 `wechat_send_file.sh <路径或URL>`；多个匹配先把候选列给用户确认，不要盲发。
6. **拍照/看摄像头**：说“拍一张 / 拍个照 / 看看家里 / 摄像头看一下”→ `photo.sh`（默认 1920x1080，自动发到来源会话）。要特定分辨率/连拍加 `--size`、`--burst`。
7. **看美剧/电影**：说“看/放某部美剧（第几季第几集）/电影”→ `play <剧名> [季] [集]`（省略=第一季第一集）；“有哪些剧/剧单”→ `list`；“下一集/继续”→ `next`；“停”→ `stop`。VLC 播到本机屏幕。
8. **备忘/待办**：说“记一下…/备忘…/待办…”→ `note.sh add "…"`；“有什么待办/列出备忘”→ `note.sh list`；“完成第 N 条/删第 N 条”→ `note.sh done N`；“清空”→ `clear`。
9. **看开发进度**：说“看看开发进度 / 项目进度 / 各项目怎么样 / 进度”→ `progress.sh`（点击 qterminal，逐个 tab 截图 opencode，合并后发来源会话）。
10. **英语口语陪练**：收到 `[英语口语] ...` 时，你是英语口语陪练——用**英文**简短回应（1-3 句）、温和指出更自然的说法，并反问一句让对话继续；回复一律 `tools/say.sh "英文"` 读出（陪练模式会自动用英文音色）。用户说中文或要翻译时，再中英对照。
11. **记单词**：说“记单词 / 背单词 / 开始背单词”→ `tools/vocab.sh start`；“停了/结束背单词”→ `stop`；要加词 → `add <英文> <中文>`。开始后弹卡片，你读单词：**读对进下一个；读错弹带中文翻译的卡片帮助记忆**。
12. **查股价/财务数据**：说“<股票>股价/多少钱/涨跌”→ `tools/stock.sh <名称或代码>`；“走势/K线”→ `kline <名称或代码> [天数]`；“估值/市盈率/市净率”→ `value <名称或代码>`；“财务/利润/ROE/毛利率”→ `fin <名称或代码> [报告期]`；“自选股”→ `list`。若用户要**看行情网页/截图/看盘** → 用 `quote_web.sh`。
13. **自绘数据大屏**：说“自绘大屏 / 汇总我的自选股 / 把指数和自选股汇总成一张图”→ `tools/dash.sh`。若只是“看行情/看盘”→ 用 `quote_web.sh` 开浏览器截图。
14. **看行情/看盘/大盘**：说“看下<股票>行情 / 大盘怎么样 / 看盘 / 行情截图”→ `tools/quote_web.sh [名称或代码]`（不传=上证指数）。它会用浏览器打开搜狐行情页并全屏截图发来源会话。
15. **打开微博搜索页(截图)**：说“打开微博 / 微博搜 <关键词>，要网页截图”→ `tools/weibo.sh <关键词>`（打开搜索页并全屏截图）。**要找/发某明星的图片** → 用 `weibo_imgs.sh`。
16. **下载微博图**：说“下载微博图 <明星> / 抓 <明星> 的微博图 / 找 <明星> 的图”→ `tools/weibo_imgs.sh <明星>`。**默认抓 1..20 页**（也可 `N`、`A-B` 或 `all`）。用**微博 cookie（存在 ~/.env，长期免授权）** curl 抓 `s.weibo.com` 搜索页，解析帖子图片并自动把小图换成大图，**保存到 ~ 下的目录**并报告下载张数（默认不发微信）。只有用户明确说“发我微信/发过来”才加 `--to` 发送；cookie 过期（抓不到）时才用 `--refresh-cookie` 从已登录 Chrome 重取一次。
17. **下载图片URL**：当你已拿到图片 URL（来自网页/接口）→ `tools/send_images.sh --save <目录> <url...>`（自动把 /orj360//thumb150//mw690/ 等**小图换成 /large/ 大图**后下载并保存，报告张数）。加 `--to 会话` 才发微信。看某明星微博图请用 `weibo_imgs.sh`。
18. **截屏发我 / 截图发我 / 屏幕发我** → `tools/wechat_shot.sh`（可选 `--to <会话名>`）。截取当前屏幕并用微信发送。若用户想截的是某个网页/地图，先用浏览器打开并置于前台再调用。
19. **手机操作**：用户说“看下手机/手机截个屏/操作手机”→ 用 `tools/phone.sh screen` 得路径，再 `tools/wechat_send_file.sh <路径>` 发回；要点击/滑动/输入/打开应用就用对应子命令（中文输入用 `phone.sh type`）。**只用白名单子命令**，不要拼 `adb` 原始命令。

_（本文件由 plugin.sh 生成，被 opencode 通过 instructions 自动加载；改工具后重跑 index 即可。）_
