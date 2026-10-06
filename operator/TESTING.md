# 测试与回归（TESTING.md）

> 用途：登记各能力的**测试项**与结果；每次新增/修改功能后照此做**回归测试**。
> 工具清单以 [`operator/TOOLS.md`](TOOLS.md) 为准（由 `operator/plugin.sh index` 自动生成，勿手改）。

---

## 1. 两种测试方式

### A. 全自动闭环（推荐，回归用）
手机微信发指令 → PC 微信同步 → `wechat-ocr/bridge.sh` OCR → 大脑执行 → 回程到手机。
用 `operator/tools/phone.sh` 驱动手机，并截图核对**两端**。

```bash
# 环境检查
operator/tools/phone.sh status                          # 手机已连接/已授权
tmux ls                                                 # my-agent-brain / wxbridge 在线

# 从手机发一条指令
operator/tools/phone.sh open com.tencent.mm
operator/tools/phone.sh tap <输入框X> <输入框Y>
operator/tools/phone.sh type "ai 现在几点"               # 中文（自动切 ADBKeyboard 后复原）
operator/tools/phone.sh tap <发送X> <发送Y>

# 核对（读两端）
operator/tools/phone.sh screen /tmp/phone.png           # 手机端回程
import -window "$(xdotool search --name 微信 | head -1)" /tmp/pc.png   # PC 端
```

### B. 直连单工具（快速定位 bug）
```bash
operator/tools/<name>.sh <参数>        # 直接看 stdout / 效果，绕过大脑
```
> 注：直连只验证工具本身；`A` 还额外验证 入口→大脑→白名单→回程 整条链路。

---

## 2. 判定标准

| 标记 | 含义 |
|------|------|
| ✓ | 通过（符合预期） |
| ✗ | 失败（备注写现象/报错） |
| — | 跳过（不适用，或有副作用暂不跑） |

---

## 3. 测试清单

### 3.1 冒烟项（每次回归必跑）

| # | 工具 | 测试项目 | 触发指令（手机发） | 预期 | 通过 | 测试时间 | 备注 |
|---|------|----------|--------------------|------|------|----------|------|
| S1 | bridge | 微信入口转发 | `ai 现在几点` | bridge 打印 `[微信输入:文件传输助手] …` | ✓ | 2026-10-06 21:50 | OCR 可能花，标签需可辨 |
| S2 | now.sh | 问时间 | `ai 现在几点` | 回 `ai助手 现在是…` | ✓ | 2026-10-06 21:50 | 大脑 18.7s |
| S3 | phone.sh | 手机截屏 | `ai 看下手机` | 收到手机屏截图 | ✓ | 2026-10-06 21:33 | screen→wechat_send_file |
| S4 | wechat_send_file.sh | 回程发图 | （由 S3 触发） | 来源会话收到图 | ✓ | 2026-10-06 21:20 | |
| S5 | wechat_shot.sh | 截屏发我（截当前屏） | `ai 截个屏发我` | 收到截图 | ✓ | 2026-10-06 22:01 | 大脑按规则18走 wechat_shot；修复见「已知坑」 |
| S6 | wechat_shot.sh | 截当前前台 | `ai 截图发我`（浏览器在前台） | 收到浏览器截图 | ✓ | 2026-10-06 21:24 | Alt+A→剪贴板→粘贴 |

### 3.2 全量清单（回归时逐项）

| # | 工具 | 测试项目 | 触发指令 / 直连命令 | 预期 | 通过 | 测试时间 | 备注 |
|---|------|----------|----------------------|------|------|----------|------|
| 1 | now.sh | 当前时间 | `ai 现在几点了` | 文本回复时间 | ✓ | 2026-10-06 21:50 | |
| 2 | screenshot.sh | 全屏截屏 | `screenshot.sh /tmp/x.png`（直连） | 输出 2560x1440 PNG | ✓ | 2026-10-06 21:54 | 工具本身正常 |
| 3 | wechat_shot.sh | 截当前屏发微信 | `ai 截个屏发我` / `ai 截图发我` | 图片到来源会话 | ✓ | 2026-10-06 22:01 | 见「已知坑」Alt+A 说明 |
| 4 | phone.sh screen | 手机截屏 | `ai 看下手机 / 手机截个屏` | 手机截图到来源会话 | ✓ | 2026-10-06 21:33 | |
| 5 | phone.sh tap/type/open | 手机操作 | 直连 `phone.sh open com.tencent.mm`、`tap`、`type "中文"` | 手机相应动作 | ✓ | 2026-10-06 21:46 | type 依赖 ADBKeyboard |
| 6 | wechat_send.sh | 发文本 | 直连 `wechat_send.sh "test"` | 文件传输助手收到 | ✓ | 2026-10-06 21:45 | 自动加 `ai助手` 前缀 |
| 7 | wechat_send_file.sh | 发文件/图 | `wechat_send_file.sh /tmp/x.png` | 收到文件 | ✓ | 2026-10-06 21:20 | |
| 8 | say.sh | TTS 出声 | `say.sh "你好"` / 语音入口 | USB 音响出声 | | | |
| 9 | photo.sh | USB 摄像头拍照 | `ai 拍一张` | 照片到来源会话 | | | |
| 10 | music.sh | 音乐 | `ai 放周杰伦` / `随机放一首` / `停` | VLC 播放/停止 | | | |
| 11 | tv.sh | 美剧/电影 | `ai 看老友记` / `下一集` / `停` | VLC 播放 | | | |
| 12 | image.sh | 生成图片 | `ai 画一张猫` | 图片到来源会话 | | | |
| 13 | find_file.sh | 搜文件 | `ai 找 xxx 文件` | 返回本机/WebDAV 匹配 | | | |
| 14 | note.sh | 备忘 | `ai 记一下…` / `有什么待办` | 增/列 | | | |
| 15 | stock.sh | 股票 | `ai 茅台多少钱` / `kline 茅台` / `value` / `fin` / `list` | 行情/图表 | | | |
| 16 | dash.sh | 自选股大屏 | `ai 自绘大屏` | 大屏图到来源会话 | | | |
| 17 | quote_web.sh | 看盘网页截图 | `ai 看下大盘` | 搜狐行情截图 | | | |
| 18 | weibo.sh | 微博搜索截图 | `ai 微博搜 周杰伦` | 搜索页截图 | | | |
| 19 | weibo_imgs.sh | 下载微博图 | `ai 下载微博图 刘浩存` | 存 `~/微博图/刘浩存/` 并报张数 | ✓ | 2026-10-06 20:00 | 375 张/38s |
| 20 | send_images.sh | 下载图片URL | `send_images.sh --save /tmp <url>` | 保存并报张数 | | | |
| 21 | progress.sh | 开发进度 | `ai 看看开发进度` | 合并截图到来源会话 | | | |
| 22 | remote.sh | 集群管理 | `ai 集群状态` | tmux/opencode 列表 | | | |
| 23 | browser.sh | 打开网页 | `ai 新开个标签页` | Chrome 新标签 | | | |
| 24 | open_app.sh | 打开应用 | `ai 打开终端` | 对应应用启动 | | | |
| 25 | english.sh | 英语陪练 | `english.sh start` / `stop` / `status` | 进入/退出陪练 | | | |
| 26 | vocab.sh | 记单词 | `ai 开始背单词` / `add x y` / `list` | 弹卡/发音判定 | | | |
| 27 | gemini_out.sh | 结果分发 | `gemini_out.sh wechat "…"` | 按目标转发 | | | |

### 3.3 链路级测试

| # | 测试项目 | 方法 | 预期 | 通过 | 测试时间 | 备注 |
|---|----------|------|------|------|----------|------|
| L1 | 微信入口白名单 | 从**非白名单**会话发 `ai …` | 不转发 | | | |
| L2 | 标签容错 | 发 `ai助手 x` / `#ai x` | 均识别为指令 | | | |
| L3 | 回程到来源会话 | `--to <会话>` | 只回该会话，不发错人 | | | |
| L4 | 防自循环 | 大脑回复不被当新指令 | 无重复触发 | | | |
| L5 | guard 兜底 | 直连含 `&&`/`;` 的命令 | 被拦截/拒绝 | | | |
| L6 | 语音入口 | `[语音输入] 现在几点` | 按规则语音/微信回 | | | |
| L7 | 手机→大脑→手机 全自动闭环 | 3.1 的 S1+S2 | 两端截图核对一致 | ✓ | 2026-10-06 21:50 | |

---

## 4. 回归流程（新增/修改功能后）

1. `operator/plugin.sh index`  → 刷新 `TOOLS.md`（工具清单/规则）。
2. 重启大脑：`tmux kill-session -t my-agent-brain && setsid operator/start.sh --bg`，
   再补建 tui 窗口（本机 `ensure_tui.sh` 有时建不出）：
   ```bash
   tmux new-window -d -t my-agent-brain -n tui \
     "cd /opt/my-agent/operator && opencode attach http://localhost:4097; echo; echo '[tui exited] enter'; read _"
   ```
3. 确认 `wxbridge` 在线（`tmux ls`；不在则 `tmux new-session -d -s wxbridge -n bridge /opt/my-agent/wechat-ocr/bridge.sh`）。
4. 先跑 **3.1 冒烟项**；再按改动的工具跑对应项 + 关键项。
5. 把结果填回上表（通过/时间/备注）；失败则修复后**重测该行**并在备注记录。

> 只改工具实现、未动 `TOOLS.md` 的：可跳过第 1-2 步，直接测。

---

## 5. 已知坑（排障）

- **OCR 读花预览**：bridge 读的是浅灰小字预览，易错（如 `现在几点`→`现在点`）。
  已做「灰度 + level 20%,85%」预处理 + 标签容错（`ai`/`ai助手` 及变体 `al`/`l`/`1`）。
  排查：`WECHAT_ONCE=1 WECHAT_DRY=1 wechat-ocr/bridge.sh` 看实际读到的预览。
- **`wechat_shot.sh`（Alt+A 截屏发微信）两个坑**：
  1) **微信在前台**时，Alt+A 后「双击」只截到 ~90B 空图 → 须改用「拖拽框选整屏 + 双击」；
     非微信前台双击即可（脚本已自动兜底：先双击，图太小再拖拽）。
  2) **Ctrl+V 后不能立刻回车**：图还没上传/暂存完，回车发不出去（表现为图卡在输入框）。
     脚本已改为等 4s + 点一下输入框确保聚焦 + 连按两次回车。
- **手机中文输入**：`adb input text` 不支持中文；用 `phone.sh type`（自动切 ADBKeyboard，用完复原）。
  首次需 `adb install ADBKeyboard.apk`（`com.android.adbkeyboard`）。
- **`phone.sh` 坐标**：分辨率见 `phone.sh status`；先用 `phone.sh screen` 截图定位。
- **重启大脑会牵连 tmux**：别用管道接 `start.sh`（子进程占住 stdout 会导致超时被 kill，连 tmux server 一起没）。
  安全法：`setsid … >/tmp/brain_start.log 2>&1 </dev/null &`，完成后核对 `wxbridge` 是否还在。

---

*文档版本: 1.0 · 创建: 2026-10-06*
