# WeChat OCR 测试脚本

> ⚠️ **全部脚本当前标记为「未验证」** — 需重新测试确认功能正常。

## 环境要求

```bash
export LD_LIBRARY_PATH=./lib:/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib
export LUA_PATH="/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;;"
export LUA_CPATH="/usr/local/lualib/?.so;;"
```

或直接用 `run.sh`。

---

## 测试脚本

### 1. test_3columns.lua — 三列结构检测 (未验证)

检测微信窗口的三列结构，输出分界位置和标注图。

```bash
luajit tests/test_3columns.lua
```

| 输出 | 说明 |
|------|------|
| 控制台 | 三列分界位置（px和百分比） |
| ~/wechat_3cols_test.png | 标注图 |

**边界定位**: 用第二列右侧短文本（3-8字符）+40px 动态定位，无固定比例，自适应窗口大小。

---

### 2. test_icons.lua — 全窗口小图标检测 (未验证)

```bash
luajit tests/test_icons.lua
```

输出: `~/wechat_icons.png`

---

### 3. test_third_icons.lua — 第三列小图标检测 (未验证)

先 OCR 定位第三列 → 再扫描找图标 → 标注。

```bash
luajit tests/test_third_icons.lua
```

输出: `~/wechat_third_icons.png`

---

### 4. test_send_file.lua — 发送文件 (未验证)

点文件图标 → 粘贴文件名 → 回车。

```bash
luajit tests/test_send_file.lua [文件路径]
# 默认: ~/wechat_third_icons.png
luajit tests/test_send_file.lua ~/video.mp4
```

---

### 5. test_screenshot.lua — 截图发送 (未验证)

点截图图标 → 框选全屏 → 双击确认 → 发送。

```bash
luajit tests/test_screenshot.lua
```

---

### 6. test_search.lua — 搜索联系人 (未验证)

```bash
# 只搜索
luajit tests/test_search.lua [关键词]
luajit tests/test_search.lua "小王"

# 搜索 + 点第一个结果 + 发消息
luajit tests/test_search.lua [关键词] [消息]
luajit tests/test_search.lua "小王" "你好！"
```

搜索框位置: 窗口 (wx+180, wy+50)

---

### 7. test_contacts_search.lua — 通讯录搜索 (未验证)

点通讯录图标 → 搜索。

```bash
luajit tests/test_contacts_search.lua [关键词]
```

---

### 8. test_first_column.lua — 第一列图标点击 (未验证)

依次点击第一列7个图标。

```bash
luajit tests/test_first_column.lua
```

| 图标 | 位置 |
|------|------|
| 聊天 | (wx+40, wy+110) |
| 通讯录 | +60px |
| 收藏 | +60px |
| 朋友圈 | +60px |
| 小程序 | +60px |
| 更多 | +60px |
| 设置 | +60px |

---

### 9. test_unread_detect.lua — 未读消息检测（旧版）(未验证)

检测第二列中红色背景的数字（未读标记）。

```bash
luajit tests/test_unread_detect.lua
```

检测方法: OCR全窗口 → 在第二列中找纯数字 → 输出

---

### 10. test_two_lines.lua — 第二列聊天条目检测 + 自动点击 (未验证)

检测第二列聊天列表条目，等距标注，并依次点击/悬停（服务号只悬停不点击）。

```bash
luajit tests/test_two_lines.lua
```

| 输出 | 说明 |
|------|------|
| 控制台 | 行位置、服务号标记 |
| ~/wechat_two_lines_annotated.png | 标注图 |

---

### 11. test_avatar_badges.lua — 头像红点/未读标记检测 (未验证)

检测聊天列表头像上的红色未读标记（小红点和数字）。

```bash
luajit tests/test_avatar_badges.lua
```

| 输出 | 说明 |
|------|------|
| 控制台 | 红点位置、匹配条目编号 |
| ~/wechat_avatar_badges.png | 标注图（红框标记有未读的条目） |

**检测方法**: ImageMagick 连通分量分析 → 严格红色阈值（R>G*2.2, G<0.5）→ 位置匹配 → 额外检测无文字条目（如微信支付）

**红点特征**:
| 类型 | 检测方式 | 标注 |
|------|---------|------|
| 小红点（无数字） | 严格红色阈值 + 连通分量 5~20px | 🔴 红框 |
| 红底白字数字 | 同红色检测 + 中心白色像素判断 | 🔴 红框 |
| 群消息 N条 | OCR 文本匹配 `%d+条` | 📝 红框 |
| 无文字条目 | 未匹配红点 x<200, y>100 | 🟠 橙色框 "?" |

---

### 12. test_avatars.lua — 第二列头像检测（OCR）(未验证)

完全用 OCR 检测第二列中的头像文字（方形文字框），不涉及颜色检测。

```bash
luajit tests/test_avatars.lua
```

输出: 头像区域文字框的坐标和文本

---

### 13. test_ai_search.lua — Chrome AI 搜索 (未验证)

Chrome 新标签 → 地址栏输入 → Tab → 回车（AI 模式），支持自定义问题。

```bash
luajit tests/test_ai_search.lua "问题"
luajit tests/test_ai_search.lua "马斯克最新身价多少"
```

**获取结果**: Ctrl+A → Ctrl+C 复制页面内容后读取剪贴板。

---

### 14. test_open_chrome.lua — 打开 Chrome (未验证)

```bash
luajit tests/test_open_chrome.lua
```

---

### 15. google_ai_qa.lua — Google AI 模式问答 (未验证)

新空白标签 → 输入问题 → 回车搜索 → 截图 + OCR 读结果。

```bash
luajit tests/google_ai_qa.lua
```

---

### 16. google_ai_test.lua — Google AI 模式测试 (未验证)

打开 Google → 输入问题 → 点 AI 模式按钮 → 截图。

```bash
luajit tests/google_ai_test.lua
```

---

### 17. ai_to_wechat.lua — AI 搜索 → 微信发送 (未验证)

Chrome AI 搜索 → OCR 读结果 → 微信搜索文件传输助手 → 粘贴发送。

```bash
luajit tests/ai_to_wechat.lua
```

---

### 18. monitor.lua — 微信消息监控（Lua版本）(未验证)

每 5 分钟检测微信未读红点，支持单次模式和守护模式。

```bash
# 后台运行守护进程
luajit tests/monitor.lua &

# 只检测一次
luajit tests/monitor.lua --once
```

**检测方法**: 截图 → ImageMagick 连通分量分析红点 → 输出未读数

---

### 19. news_execute.lua — 文件传输助手自动回复 (未验证)

检测文件传输助手未读 → 点进去 → 右键复制最新消息 → 回复"收到！马上处理"+引用原文。

```bash
luajit tests/news_execute.lua
```

**依赖**: `wechat_ocr.badge_detect` 模块

---

### 20. chrome_bridge.lua — Chrome DevTools MCP 桥 (未验证)

通过 JSON-RPC 协议与 Chrome DevTools MCP 交互，支持导航、截图等操作。

```bash
luajit tests/chrome_bridge.lua "打开 https://www.example.com 并截图"
luajit tests/chrome_bridge.lua "搜索 小红书"
```

**依赖**: `chrome-devtools-mcp@latest` (通过 npx 自动安装)

---

### 21. monitor — C 守护进程（微信消息监控）(未验证)

每 5 分钟检测微信未读红点，编译运行：

```bash
# 编译
cd /opt/my-agent/wechat-ocr
gcc -O2 -o monitor monitor.c

# 运行守护进程
./monitor &
# 日志: /tmp/wechat_monitor.log

# 单次检测
./monitor --once
```

**检测流程**: 点底部面板微信图标 → 截图 → ImageMagick 红色分析 → 连通分量匹配

---

## 统一API

```lua
local robot = require("wechat_robot")
robot.init()
robot.send("你好")
robot.send_file("a.mp4")
robot.screenshot()
robot.search("小王")
robot.contacts_search("张三")
robot.click_sidebar(3)
robot.capture()
robot.monitor({on_message=fn})
robot.set_record(true)  -- 开启录像
```

详见 `wechat_robot.lua`。

---

## 文件清单

```
tests/
├── TEST.md                     本文档
├── test_3columns.lua           三列结构检测           (未验证)
├── test_icons.lua              全窗口图标             (未验证)
├── test_third_icons.lua        第三列图标             (未验证)
├── test_send_file.lua          发送文件               (未验证)
├── test_screenshot.lua         截图发送               (未验证)
├── test_search.lua             搜索联系人             (未验证)
├── test_contacts_search.lua    通讯录搜索             (未验证)
├── test_first_column.lua       第一列图标             (未验证)
├── test_unread_detect.lua      未读检测（旧版）       (未验证)
├── test_two_lines.lua          第二列条目+自动点击    (未验证)
├── test_avatar_badges.lua      头像红点检测           (未验证)
├── test_avatars.lua            头像OCR检测            (未验证)
├── test_ai_search.lua          Chrome AI 搜索        (未验证)
├── test_open_chrome.lua        打开 Chrome           (未验证)
├── google_ai_qa.lua            Google AI问答         (未验证)
├── google_ai_test.lua          Google AI测试         (未验证)
├── ai_to_wechat.lua            AI→微信发送           (未验证)
├── monitor.lua                 未读监控（Lua版）      (未验证)
├── news_execute.lua            文件传输助手自动回复   (未验证)
├── chrome_bridge.lua           Chrome MCP桥          (未验证)
├── monitor.c                   未读监控 C 源码        (未验证)
├── monitor                     未读监控（已编译）
├── mark_columns.py             标注图生成
├── find_icons.py               图标检测
├── find_third_icons.py         第三列图标
└── find_red_badges.py          红色检测
```

---

*更新日期: 2026-06-19*
*状态: 全部脚本待验证*
