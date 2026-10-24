# 项目能力清单（Capabilities）

> 当前白名单共 **35 个工具**；完整参数与逐条规则以 `operator/TOOLS.md` 为准。
> 本文按场景汇总，供大脑快速判断“有没有现成能力”。
> 更新时间：2026-10-24

## 一、通讯 / 回程
- `wechat_send.sh`：发微信文本
- `wechat_send_file.sh`：发文件/图片，支持本地路径或 WebDAV URL
- `wechat_shot.sh`：截桌面/指定应用并直接发微信
- `screenshot.sh`：只截本机全屏，返回路径，不发送
- `say.sh`：USB 音响 TTS；支持 `--voice` 克隆音色
- `voices.sh`：克隆音色列表/注册/删除/发声

## 二、摄像头 / 音频 / 识别
- `camera.sh`：USB / EZVIZ 客厅 / EZVIZ 门口 / TP-Link / HLS / RTSP 抓一帧或录像
  - EZVIZ 地址缺失或失效时自动刷新，不再需要独立刷新脚本
- `camera_grid.sh`：四路抓帧 → 2×2 拼图 → 发微信
- `detect.sh`：YOLOv8n 原生 C++ 检测
  - `--src keting|menkou|usb|<图片>`
  - `--grid`：四路分别检测，按摄像头汇总人数，并输出带绿框拼图
  - 限制：遮挡、躺卧、远景可能漏检
- `listen_cam.sh`：监听/录制摄像头音频
  - `keting` / `menkou` / `tplink` / `usb`
  - 小机箱 USB 麦克风尚未接入

## 三、微博 / 图片收集
- `weibo.sh`：打开微博搜索页并截图
- `weibo_hot.sh`：微博实时热搜 → 排版图 + 文字
- `weibo_imgs.sh`：按关键词抓微博图，自动小图换大图，保存到 `~/微博图/<关键词>/`
- `weibo_album.sh`：按昵称/uid 下载微博相册大图
- `send_images.sh`：通用图片 URL 下载器；可保存、发微信

## 四、搜索 / 问答 / 资讯
- `google_search.sh`：Chrome CDP/DOM 谷歌搜索/新闻 → 排版图 + 文字
- `gemini.sh`：Google Gemini 问答；默认图文发微信，`--display` 只输出文本
- `git_trending.sh`：GitHub Trending → 排版图 + 文字
- `english_daily.sh`：随机科技媒体文章 → 中英对照 + 生词 → 图文发微信

## 五、图像 / 视频
- `image.sh`：文生图（本机 SD/ComfyUI），默认 2560×1440，可出小红书/朋友圈尺寸
- `img_video.sh`：提示词出图或复用图片目录 → 竖版 MP4
- `video_dub.sh`：给已有视频配音 + 字幕，可克隆音色
- `iso_native.sh`：等距图/动画（PNG/GIF/MP4）
  - **不是文生图**：只能渲染 `~/iso_flutter` 中已写好的图脚本
  - 新图需先写 Lua/Dart 脚本并重新构建

## 六、音乐 / 文件
- `music.sh`：本地/WebDAV 搜索播放 + 在线 FLAC
- `find_file.sh`：本机 + WebDAV 文件名搜索

## 七、桌面 / 终端 / 手机
- `termctl.sh`：qterminal 标签数、截图、向指定 tab 注入指令
- `term_progress.sh`：逐个 qterminal/opencode tab 截图，纵向拼图后发微信
- `phone.sh`：ADB 手机控制：截屏、点击、滑动、按键、中文输入、应用管理
- `chrome_debug.sh`：启动固定端口 9222 的专用调试 Chrome，供 MCP/CDP 使用

## 八、设备
- `vacuum.sh`：科沃斯 DEEBOT 控制：清扫、回充、找机、吸力/水量、状态/电量
- `ebook.sh`：Kindle DXG 阅读器：读书、翻页、跳页、字号、目录、截屏、朗读
  - 当前无设备时 `state` 会明确报未连接

## 九、财经 / 大屏
- `dash.sh`：指数 + 自选股 + K 线点阵风大屏图
  - 当前不提供独立股票文本查询工具

## 十、后台 / 维护
- `jobs.sh`：后台任务列表、日志、状态、停止
- `dev.sh`：项目规范、能力列表、工具模板、索引、commit/push、重启

## 关键约束
- 运行时**不依赖 Python**；新能力用 Lua（本机/系统/音视频/终端）或 JS（浏览器/CDP）
- 浏览器网页交互统一走 chrome-devtools MCP / `agentkit.cdp`
- 已删除且不再提供：独立股票查询、单张 USB 拍照、`quote_web`、浏览器 `browser.sh`、英语陪练入口、记单词卡片、摄像头喇叭喊话
- 摄像头四路拼图要发微信、看家里画面 → `camera_grid.sh`
- 想知道“哪里有人” → `detect.sh --grid`；结果受 YOLO 模型限制
