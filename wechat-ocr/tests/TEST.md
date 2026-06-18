# WeChat OCR 测试脚本

## 环境要求

```bash
export LD_LIBRARY_PATH=./lib:/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib
export LUA_PATH="/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;;"
export LUA_CPATH="/usr/local/lualib/?.so;;"
```

或直接用 `run.sh`。

---

## 测试脚本

### 1. test_3columns.lua — 三列结构检测

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

### 2. test_icons.lua — 全窗口小图标检测

```bash
luajit tests/test_icons.lua
```

输出: `~/wechat_icons.png`

---

### 3. test_third_icons.lua — 第三列小图标检测

```bash
luajit tests/test_third_icons.lua
```

输出: `~/wechat_third_icons.png`

---

### 4. test_send_file.lua — 发送文件

点文件图标 → 粘贴文件名 → 回车。

```bash
luajit tests/test_send_file.lua [文件路径]
# 默认: ~/wechat_third_icons.png
luajit tests/test_send_file.lua ~/video.mp4
```

---

### 5. test_screenshot.lua — 截图发送

点截图图标 → 框选全屏 → 双击确认 → 发送。

```bash
luajit tests/test_screenshot.lua
```

---

### 6. test_search.lua — 搜索联系人

```bash
luajit tests/test_search.lua [关键词]
luajit tests/test_search.lua "小王"
```

搜索框位置: 窗口 (wx+180, wy+50)

---

### 7. test_contacts_search.lua — 通讯录搜索

点通讯录图标 → 搜索。

```bash
luajit tests/test_contacts_search.lua [关键词]
```

---

### 8. test_first_column.lua — 第一列图标点击

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

### 9. test_unread_detect.lua — 未读消息检测（旧版）

检测第二列中红色背景的数字（未读标记）。

```bash
luajit tests/test_unread_detect.lua
```

检测方法: OCR全窗口 → 找数字 → 检查像素颜色（R>160, R-G>50）

---

### 10. test_two_lines.lua — 第二列聊天条目检测 + 自动点击

检测第二列聊天列表条目，等距标注，并依次点击/悬停。

```bash
luajit tests/test_two_lines.lua
```

| 输出 | 说明 |
|------|------|
| 控制台 | 行位置、服务号标记 |
| ~/wechat_two_lines_annotated.png | 标注图 |

---

### 11. test_avatar_badges.lua — 头像红点/未读标记检测

检测聊天列表头像上的红色未读标记（小红点和数字）。

```bash
luajit tests/test_avatar_badges.lua
```

| 输出 | 说明 |
|------|------|
| 控制台 | 红点位置、匹配条目编号 |
| ~/wechat_avatar_badges.png | 标注图（红框标记有未读的条目） |

**检测方法**: ImageMagick 连通分量分析 → 严格红色阈值（R>G*2.2, G<0.5）→ 位置匹配 → 跳过公众号/服务号

---

### 12. test_ai_search.lua — Chrome AI 搜索

Chrome 新标签 → 地址栏输入 → Tab → 回车（AI 模式），支持自定义问题。

```bash
luajit tests/test_ai_search.lua "问题"
luajit tests/test_ai_search.lua "马斯克最新身价多少"
```

**获取结果**: Ctrl+A → Ctrl+C 复制页面内容后读取剪贴板。

---

### 13. ai_to_wechat.lua — AI 搜索 → 微信发送

Chrome AI 搜索 → OCR 读结果 → 微信搜索文件传输助手 → 粘贴发送。

```bash
luajit tests/ai_to_wechat.lua
```

---

### 14. test_open_chrome.lua — 打开 Chrome

```bash
luajit tests/test_open_chrome.lua
```

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
├── TEST.md                  本文档
├── test_3columns.lua        三列结构检测
├── test_icons.lua           全窗口图标
├── test_third_icons.lua     第三列图标
├── test_send_file.lua       发送文件
├── test_screenshot.lua      截图发送
├── test_search.lua          搜索联系人
├── test_contacts_search.lua 通讯录搜索
├── test_first_column.lua    第一列图标
├── test_unread_detect.lua   未读检测（旧版）
├── test_two_lines.lua       第二列条目检测+自动点击
├── test_avatar_badges.lua   头像红点检测
├── test_ai_search.lua       Chrome AI 搜索
├── test_open_chrome.lua     打开 Chrome
├── ai_to_wechat.lua         AI→微信发送
├── mark_columns.py          标注图生成
├── find_icons.py            图标检测
├── find_third_icons.py      第三列图标
└── find_red_badges.py       红色检测
```
