<!-- 自动生成 by operator/plugin.sh index —— 请勿手改；新增工具后重跑即可 -->
# 工具与技能（白名单）

**只能**调用下列 `operator/tools/*.sh`。除此之外的任何命令、文件读写、网络一律禁止。
一条指令只调一个工具；禁止用 `&&`、`;`、`|`、重定向拼接（会被 guard 拦截）。

| 工具 | 用途 | 用法 |
|------|------|------|
| `tools/camera_grid.sh` | 抓 EZVIZ 客厅/门口、TP-Link、USB 四路画面，拼图发送微信 | `tools/camera_grid.sh [--to 会话] [--no-send] [--out 路径]` |
| `tools/camera.sh` | 读摄像头(USB/RTSP/HLS/TP-Link)一帧给 Agent 读图：优先用常驻界面(Flutter)产出的实时帧，其次自抓；也可录像 | `tools/camera.sh [--usb N | --rtsp URL | --hls URL | --ezviz keting|menkou | --tplink] [--help] [--out 路径] [--live 秒] [--bg]` |
| `tools/chrome_debug.sh` | 每次启动前同步 profile，再用固定调试端口起专用 Chrome，供 chrome-devtools MCP(--browser-url) 连接（免反复授权） | `tools/chrome_debug.sh [端口]        # 默认 9222` |
| `tools/dash.sh` | 股票大屏（点阵风·暗色：指数环+自选股+小K线） | `tools/dash.sh [--to 会话] [--show] [--no-send]` |
| `tools/detect.sh` | 对摄像头抓帧做 YOLO 目标识别（**原生 C++/libtorch**，无 Python）：框出人/物并返回带框图路径 | `tools/detect.sh [--src usb|keting|menkou|<图片路径>] [--grid] [--conf 0.35] [--to 会话]` |
| `tools/dev.sh` | 本项目结构与规范；新能力=一个**走专用 Chrome(免授权登录)+CDP/DOM 的网页工具**（能力来自网页，安全）；支持新建/索引/提交(可回滚)/重启 | `tools/dev.sh info | caps | list | new <name> | index | commit [msg] | push | restart` |
| `tools/douyin.sh` | 抖音作品：前 N 条下载到 ~/douyin/<uid> （文案/标签/视频；高赞转 wav 供克隆）；默认抓自己，可指定 uid | `tools/douyin.sh list [N] [<主页URL>|--uid <sec_uid>|--url <主页URL>]                 # 列前 N 条(id/赞/文案/标签)` |
| `tools/ebook.sh` | 操作连接的 Kindle 电纸书：读书、翻页、跳页、调字号、看目录；截当前屏；读屏文本；朗读当前页；自测 | `tools/ebook.sh say "读异类" | "下一页" | "上一页" | "跳到第20页" | "第3章" | "字号大" | "目录" | "书架"` |
| `tools/english_daily.sh` | 从多家科技媒体(HN/Ars/TechCrunch/Verge/Wired/Engadget/Register/BBC/MIT)每天随机取一篇英文 → Gemini 中英对照+生词 → 图文发微信（图底含原文来源 URL） | `tools/english_daily.sh [<主题> | --url <url>] [--words N] [--level B1-B2] [--display] [--to 会话] [--no-send] [--fg]` |
| `tools/find_file.sh` | 按文件名关键词搜索本机文件 + WebDAV，返回匹配（本地路径 或 可下载 URL，LuaJIT 实现） | `find_file.sh <关键词> [数量=15]` |
| `tools/gemini.sh` | 用 Chrome(CDP) 问 Google AI(Gemini)；默认排版图+文字发微信，--display 仅打印回答 | `tools/gemini.sh <问题> [--display] [--to 会话] [--no-image] [--no-send] [--fg]` |
| `tools/git_trending.sh` | GitHub 今日热门：抓取 Trending → 生成排版图 → 发微信（默认文件传输助手） | `tools/git_trending.sh [--since daily|weekly|monthly] [--lang <lang>] [--limit N] [--to 联系人] [--text] [--show] [--no-send]` |
| `tools/google_search.sh` | 用 Chrome(CDP/DOM) 谷歌搜索，先生成排版图再发文字到微信（默认文件传输助手） | `tools/google_search.sh <关键词> [--news] [--to 会话] [--no-image] [--no-send]` |
| `tools/image.sh` | 生成图片并发送到微信（可指定 小红书/小红薯、朋友圈 尺寸） | `tools/image.sh [小红书|小红薯|朋友圈] "提示词" [--to 会话] [--force] [--fg]` |
| `tools/img_video.sh` | 动画/图片视频：按提示词出图，再合成竖版 MP4（默认 1080×1920，不发微信） | `tools/img_video.sh --scenes "提示词1|提示词2|…" [--out out.mp4] [--img-preset xhs|pyq] [--seconds N] [--send [--to 会话]] [--fg]` |
| `tools/iso_native.sh` | 等距解释图/动画：调用 `~/iso_flutter/bin/iso.sh`（native：Dart+Lua 引擎，Flutter 离屏渲染）生成 PNG/GIF/MP4，再发微信。**不是文生图**：只能渲染 `~/iso_flutter` 里已注册/已写好的图脚本；新图必须先写 Lua/Dart 图脚本并重新构建。 | `tools/iso_native.sh render <图名> [--ss N] [--lift 0..1] [--theme dark|light] [--out 目录] [--to 会话] [--no-send]` |
| `tools/jobs.sh` | 后台任务：列出、看日志尾部、停止、查状态 | `tools/jobs.sh list | tail <id> [行数] | stop <id> | status <id>` |
| `tools/listen_cam.sh` | 监听音频来源（EZVIZ/TP-Link/本机USB麦克风）：播放到本机音响，或录成 wav | `tools/listen_cam.sh [keting|menkou|tplink|usb] [秒数=10] [--save <路径>] [--play] [--bg]` |
| `tools/music.sh` | 无损音乐：本地(WebDAV)搜索/播放 + 在线 FLAC（LuaJIT 实现） | `tools/music.sh` |
| `tools/netmap.sh` | 扫描局域网并识别设备：读取 ARP/主机名/端口/摄像头信息，生成 devices.json、NETWORK.md 和 devices.env；供其他工具动态读取 IP 与音视频源 | `tools/netmap.sh scan | show | sources` |
| `tools/phone.sh` | 控制连接的安卓手机：截屏、点击、滑动、按键、输入(含中文)、打开应用、列出/安装应用 | `tools/phone.sh status                        # 查看是否已连接` |
| `tools/say.sh` | USB 音响发声（TTS）；可用 --voice 指定克隆音色（LuaJIT 编排） | `tools/say.sh [--voice <音色名>] [--bg] "文本"` |
| `tools/screenshot.sh` | 只截本机全屏并返回路径，不发送；摄像头拼图用 camera_grid.sh | `tools/screenshot.sh [输出路径]` |
| `tools/send_images.sh` | 下载图片（小图自动换大图）：保存目录并报张数；可同时发微信 | `tools/send_images.sh [--save 目录] [--to 会话] [--each] [--limit N] [--fg] <图片URL...>   （URL 也可从 stdin 每行一个）` |
| `tools/termctl.sh` | 控制 qterminal 中的命令行应用：列出标签数 / 截图发微信 / 向指定标签注入指令并回车执行 | `tools/termctl.sh tabs | shot [N] [--to 会话] | send <N> "<指令>" [--no-enter]` |
| `tools/term_progress.sh` | 查看开发进度：逐个 tab 截图 opencode，合并后发微信（LuaJIT 实现） | `term_progress.sh [--to 会话]` |
| `tools/vacuum.sh` | 控制科沃斯扫地机 DEEBOT（**原生 C 内核**，无 Python）：清扫/回充/找机/吸力/水量/音量/次数/续扫/AI/地毯/高级模式；并读电量/故障/网络/统计 | `tools/vacuum.sh <cmd> [arg]` |
| `tools/video_dub.sh` | 给已有视频配音+字幕（可克隆音色）；先用 --probe 生成配音比对时长，确保不超视频，再合成 | `tools/video_dub.sh <视频> "文案1|文案2|…" [--probe] [--speed 0.85] [--fit] [--ref 参考.wav] [--voice 名] [--out out.mp4] [--to 会话] [--send] [--keep-audio] [--fg]` |
| `tools/voices.sh` | 克隆音色：列出/注册/删除音色，或用指定音色发声（LuaJIT 编排） | `tools/voices.sh list | add <名> <参考.wav> ["参考文本"] | del <名> | say <名> "文本" [语速]` |
| `tools/wechat_send_file.sh` | 发送文件/图片到微信（LuaJIT 实现） | `wechat_send_file.sh <本地路径|http(s)://URL> [--to 联系人]` |
| `tools/wechat_send.sh` | 发送微信文本（LuaJIT + xdo/xclip 实现） | `wechat_send.sh "内容"                  # 默认发到当前会话（文件传输助手）` |
| `tools/wechat_shot.sh` | 截屏发微信：说「截图/截屏 <应用名>」则截该应用；不给应用则截桌面。发送到指定会话/文件传输助手 | `tools/wechat_shot.sh [--to 会话] [--app 应用名]` |
| `tools/weibo_album.sh` | 微博相册大图下载（搜昵称定 uid → 相册接口翻页取大图 → 存 ~ 报张数） | `tools/weibo_album.sh <昵称|uid> [页数 | all，默认 20] [--save 目录] [--to 会话] [--limit N]` |
| `tools/weibo_hot.sh` | 抓微博实时热搜榜，生成排版图并（可选）发文字到微信（默认文件传输助手） | `tools/weibo_hot.sh [--to 会话] [--limit N（默认15）] [--display] [--no-send]` |
| `tools/weibo_imgs.sh` | 下载微博图（打开微博搜索，抓九宫格图并小图换大图，直接存到 ~ 报张数） | `tools/weibo_imgs.sh <明星/关键词> [页数 | A-B | all，默认 20] [--save 目录] [--each] [--limit N] [--to 会话] [--refresh-cookie]` |
| `tools/weibo.sh` | 微博搜索（浏览器打开微博搜索页并全屏截图发微信） | `tools/weibo.sh <关键词> [--to 会话]` |

## 通用规则

1. 禁止读写项目源码、改系统配置、装/删软件、关机重启。
2. 需要给非默认会话发消息时，先确认对方身份，避免误发。
3. 不认识的请求 → 回复“这个我暂时不支持”，不要尝试绕过白名单。
4. **浏览器只用于网页任务**：读网页/交互走 chrome-devtools MCP，禁止用 OCR 识别网页；纯信息类（时间、算数、常识）不要动用浏览器。

## 各工具使用规则

1. **需求现有工具满足不了时**：`tools/dev.sh info` 读规范 → `tools/dev.sh new <name>` 生成网页工具模板（里层用专用 Chrome + `ak.cdp` 做 DOM 操作）→ 填逻辑 → `commit`（可回滚）→ `restart` 生效。**能力只来自网页（免授权 Chrome + CDP/DOM）**，不写碰本机任意资源的脚本，也不做浏览器扩展。
2. 说“扫描设备/看网络拓扑/更新设备 IP/刷新摄像头地址”→ `tools/netmap.sh scan`；只看当前结果用 `show`/`sources`。
3. **出声/朗读/语音回**：用 `tools/say.sh "文本"`；想用**克隆音色**发声则 `tools/say.sh --voice <音色名> "文本"`（音色用 `tools/voices.sh` 管理：list/add）。
4. **只截本机全屏** → `screenshot.sh`（返回路径，不发）；要直接发微信用 `wechat_shot.sh`；四个摄像头拼图用 `camera_grid.sh`。
5. **克隆音色 / 指定某人音色发声**：说“用 X 的声音说 … / 克隆 X 的音色 / 有哪些音色”→ 先 `tools/voices.sh list` 看已注册的。要**新增**音色需用户提供一段 **3–30 秒参考音频（.wav 路径）**：`tools/voices.sh add <名> <参考.wav> ["参考文本"]`（不给文本会用 SenseVoice 自动转写，稍慢）；然后用 `tools/say.sh --voice <名> "内容"` 发声（或 `tools/voices.sh say <名> "内容"`）。删除：`tools/voices.sh del <名>`。
6. **音乐**：说“放歌/放某某的歌/随机放一首”→ `play <歌手或歌名>`（本地库没有会自动**在线取无损 FLAC 播放**并**保存到 NAS**）；“下一首/换一首” → `next`；“停/别放了”→ `stop`；“大声点/小声点”→ `volup`/`voldown`。指定在线源用 `online <关键词> [kuwo|wyy]`。
7. **画图/生成图片**：说“画一张…/生成图片…/来个…的图”→ `image.sh "提示词"`。尺寸可**明确指定**：`小红书`/`小红薯`（3:4 竖版 1920×2560）、`朋友圈`（1:1 方图 2048×2048），默认 2560×1440 横版。用法 `image.sh [小红书|小红薯|朋友圈] "提示词"`。出图要几分钟，完成后脚本自动发微信，你只需简短确认。GPU 忙时会被拒绝，稍后再试。
8. **发文件给我**：说“把 xxx 文件发我 / 找 xxx 文件 / 发我某首歌 / 找某部美剧”→ 先 `find_file.sh <关键词>`（本机 + WebDAV 都搜）。唯一匹配就直接 `wechat_send_file.sh <路径或URL>`；多个匹配先把候选列给用户确认，不要盲发。
9. **看开发进度**：说“看看开发进度 / 项目进度 / 各项目怎么样 / 进度”→ `term_progress.sh`（点击 qterminal，逐个 tab 截图 opencode，合并后发来源会话）。
10. **抖音作品/文案/音色**：说“抓我抖音前N条作品 / 下载 <某人> 的抖音 / 要抖音文案标签”→ `tools/douyin.sh get <N>`（默认18，抓自己）。**用户直接发主页 URL（或分享短链）也可以**：`tools/douyin.sh get <N> "<url>"`（也支持 `--uid <sec_uid>`/`--url <url>`，短链会自动解析）。会下载视频到 `~/douyin/<uid>/`、生成 `文案.txt`/`标签.txt`（标签可用于发布参考），并把**点赞≥阈值(默认30)**的转成 16k wav 存 `wav/`（可 `tools/voices.sh add <名> <wav>` 克隆音色）。只看不下载用 `list <N>`。**前提：Chrome 已登录抖音且开着调试口 9222。** 默认不发微信。
11. **生成抖音素材 / 给视频配音+字幕 / 带货引流视频**：说“**生成抖音素材** / 做抖音素材 / 生成素材 / 给这个视频配音+字幕 / 给视频配字幕 / 做带货引流视频 / 给这个视频配文案和配音”→ **根据视频/商品信息自己推理写文案**（像真人口播，别念参数：①钩子→②品牌价值→③口语串讲卖点→④收尾；不出现品牌名；「防水」改「不怕水」；`App`写「官方软件」；每段≈20字、长度均衡、**可短不可超视频时长**；结尾固定「想捡漏的来我直播间」），再用本工具先 `--probe`（自动前台）比对时长、后 `--fg` 合成。默认出**3 条不同文案**（同一素材），**必须一条跑完再跑下一条（串行，切勿并发）**；可加 `--ss/--trim-end` 换裁剪段。**默认音色=克隆「话术」**（换音色 `--voice`）。默认不发微信（`--send` 才发）。
12. 需要 Chrome 供 MCP 使用时 → 先 `tools/chrome_debug.sh`（固定端口实例，免弹授权）；不要用系统默认 Chrome 直连。
13. **做图片视频/动画短片**：说“用<提示词/故事>生成图片视频 / 做动画短片 / 把这几张图做成视频”→ `tools/img_video.sh --scenes "<提示词1|提示词2>"`；已有图片用 `--imgdir <目录>`。默认后台跑，完成后文件在 `~/image/`；要发微信加 `--send [--to 会话]`。
14. **自绘数据大屏**：说“自绘大屏 / 汇总我的自选股 / 把指数和自选股汇总成一张图”→ `tools/dash.sh`。
15. **打开微博搜索页(截图)**：说“打开微博 / 微博搜 <关键词>，要网页截图”→ `tools/weibo.sh <关键词>`（打开搜索页并全屏截图）。**要找/发某明星的图片** → 用 `weibo_imgs.sh`。
16. **下载微博图**：说“下载微博图 <明星> / 抓 <明星> 的微博图 / 找 <明星> 的图”→ `tools/weibo_imgs.sh <明星>`。**默认抓 1..20 页**（也可 `N`、`A-B` 或 `all`）。用**微博 cookie（存在 ~/.env，长期免授权）** curl 抓 `s.weibo.com` 搜索页，解析帖子图片并自动把小图换成大图，**直接保存到 ~ 下的目录**并报告下载张数（默认不发微信）。只有用户明确说“发我微信/发过来”才加 `--to` 发送，**发送时也保留本地图片**；cookie 过期（抓不到）时才用 `--refresh-cookie` 从已登录 Chrome 重取一次。
17. **下载某人的微博相册（全量大图）**：说“下载 <某人> 的微博相册 / 抓 <某人> 相册的图 / <某人> 相册”→ `tools/weibo_album.sh <昵称>`。先按昵称搜出 uid（也可直接给数字 uid），再用相册接口翻页取**大图**（比搜索页快很多），直接存到 ~ 下的目录并报张数（默认不发微信；说“发我”才加 `--to`，发送时也保留本地图片）。
18. **下载图片URL**：当你已拿到图片 URL（来自网页/接口）→ `tools/send_images.sh --save <目录> <url...>`（自动把 /orj360//thumb150//mw690/ 等**小图换成 /large/ 大图**后下载并保存，报告张数）。加 `--to 会话` 同时发微信，图片仍保存在 `--save` 目录。看某明星微博图请用 `weibo_imgs.sh`。
19. **截屏发我 / 截图发我（非摄像头）** → `tools/wechat_shot.sh`（不加 --app 截的是桌面）。**要截某个应用**（如“截图 agent / 助手 / 微信 / 浏览器”）→ **必须** `tools/wechat_shot.sh --app <应用名>`。
20. 用户说“微博热 / 微博热搜 / 微博热搜榜” → `tools/weibo_hot.sh`（默认出图+发微信）；要**只要文本**加 `--display`。
21. **手机操作**：用户说“看下手机/手机截个屏/操作手机”→ 用 `tools/phone.sh screen` 得路径，再 `tools/wechat_send_file.sh <路径>` 发回；要点击/滑动/输入/打开应用就用对应子命令（中文输入用 `phone.sh type`）。**只用白名单子命令**，不要拼 `adb` 原始命令。
22. **电纸书**：用户说“在电纸书上看/读某本书、翻页、上一页/下一页、跳到第几页、调字号、看目录、把电纸书画面发我、念一下这页” → 用 `tools/ebook.sh`。读书 `ebook.sh say "读<书名>"`；翻页/跳页/字号 `say "<指令>"`；要画面 `ebook.sh shot /tmp/ebook.png` 再 `tools/wechat_send_file.sh`；要朗读 `ebook.sh speak`。不确定状态先 `ebook.sh state`。**不要**自己拼 ssh/scp 命令。
23. 用户说“每日英语 / 英语短文 / 学英语 / 来篇英语文章” → `tools/english_daily.sh`（默认随机科技媒体，出图+发微信）；只要文本加 `--display`。
24. 用户说“问 Google AI / 问 Gemini / 让 AI 回答 <问题> 并发我微信” → `tools/gemini.sh "<问题>"`；要**只要文本**供程序用 → 加 `--display`。
25. 用户说“帮我 google 搜索/查一下 <关键词> 并发我微信” → `tools/google_search.sh "<关键词>"`（默认发图+文字）；查新闻加 `--news`。
26. 用户说“今日github热门 / GitHub 今日热门 / 最近什么项目火” → 用 `tools/git_trending.sh`（默认出图并发微信）；不要动用浏览器。
27. **等距图/动画（非文生图）**：只能渲染 `~/iso_flutter` 里已注册的图；不能按提示词即时生成新图。引擎/图/规范都在独立仓 **~/iso_flutter**（框架 `iso_engine` + 应用 `app`）；本工具只是"调用它 + 发微信"。图名见 `~/iso_flutter/app/lib/main.dart` 的 `_figures`（`tmall-genie`(Lua) / `tmall-genie-dart`(Dart) / `lathe` / `tube`）。新增/改图在 ~/iso_flutter 里做（Lua：`app/lib/lua/figures/*.lua`；Dart：`main.dart`），再 `cd ~/iso_flutter/app && flutter build linux --release`。
28. 要看摄像头画面 → `tools/camera.sh`（返回图片路径，可直接读图）；要一段视频 → `--live <秒>`。
29. 说“摄像头截图发我 / 摄像头 截图发我 / 四个摄像头拼图 / 看看家里四个画面”→ `tools/camera_grid.sh`（默认发文件传输助手）；只生成不发用 `--no-send`。
30. 用户说“扫地/开始扫地”→ start；“沿边”→ edge；“定点”→ spot；“停”→ stop；“回充”→ dock；“找一下扫地机/它在哪”→ find；“开大吸力/静音”→ fan max|quiet；“地毯增压”→ carpet 1；“扫地机状态/电量/统计”→ status|battery|stats|total
31. 说“看看家里有谁 / 门前有人吗 / 四个摄像头哪里有人”→ tools/detect.sh --grid（四路拼图后识别并按摄像头报告人数）；单路用 --src keting|menkou；要发回用 --to
32. 说“听听客厅/门口/TP-Link/本机麦克风的声音/有没有动静”→ tools/listen_cam.sh keting|menkou|tplink|usb 10（默认外放）；只想存文件用 --save
33. 长任务返回 `job=<id>` 后，用 `tools/jobs.sh tail <id>` 看进度/结果；`list` 看全部；`stop <id>` 停止。
34. 说“命令行/终端有几个任务(标签)”→ 只调 `tools/termctl.sh tabs`，把它输出的 **任务数** 直接回复给用户（不用解释）。

_（本文件由 plugin.sh 生成，被 opencode 通过 instructions 自动加载；改工具后重跑 index 即可。）_
