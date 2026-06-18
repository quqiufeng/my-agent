# WeChat OCR 测试脚本

## 环境要求

```bash
export LD_LIBRARY_PATH=./lib:/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib
export LUA_PATH="/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;;"
export LUA_CPATH="/usr/local/lualib/?.so;;"
```

或直接用 `run.sh`（已设好环境变量）。

---

## 测试脚本

### 1. test_3columns.lua — 三列结构检测

扫描微信窗口，用时间戳定位第三列边界。

```bash
luajit tests/test_3columns.lua
```

| 输出 | 说明 |
|------|------|
| 控制台 | 三列分界位置（px和百分比） |
| ~/wechat_3cols_test.png | 标注图 |

---

### 2. test_icons.lua — 全窗口小图标检测

扫描整个微信窗口，找方形暗色块（过滤文字）。

```bash
luajit tests/test_icons.lua
```

| 输出 | 说明 |
|------|------|
| 控制台 | 图标总数 |
| ~/wechat_icons.png | 标注图 |

---

### 3. test_third_icons.lua — 第三列小图标检测

OCR定位第三列 → 输入框上方250px → 扫描图标。

```bash
luajit tests/test_third_icons.lua
```

| 输出 | 说明 |
|------|------|
| 控制台 | 第三列位置、图标数 |
| ~/wechat_third_icons.png | 标注图 |

---

### 4. test_send_file.lua — 发送文件

点文件图标 → 粘贴文件名 → 回车选择+发送。

```bash
luajit tests/test_send_file.lua [文件路径]

# 默认发送 ~/wechat_third_icons.png
# 也可指定文件:
luajit tests/test_send_file.lua ~/wechat_send_demo.mp4
```

流程：
1. OCR定位第三列和输入框
2. 计算文件图标位置（col3+130, input_y-40）
3. 点击文件图标
4. 剪贴板粘贴文件名 → 回车确认 → 回车发送

---

### 5. test_screenshot.lua — 截图发送

点截图图标 → 框选全屏 → 双击确认 → 发送。

```bash
luajit tests/test_screenshot.lua
```

流程：
1. OCR定位第三列，计算截图图标位置（col3+168, input_y-40）
2. 点击截图图标进入截图模式
3. 从 (0,0) 拖选到 (2560,1440) 框选全屏
4. 移到屏幕中心 (1280,720) 双击确认
5. 回车发送

---

### 6. test_search.lua — 搜索联系人

点击第二列顶部搜索框 → 输入关键词 → 回车。

```bash
luajit tests/test_search.lua [搜索词]

# 默认搜索 "小王"
luajit tests/test_search.lua "张三"
```

---

### 7. test_contacts_search.lua — 通讯录搜索

先点第一列第2个图标（通讯录） → 再点搜索框 (wx+160, wy+50) → 输入关键词 → 回车。

```bash
luajit tests/test_contacts_search.lua [搜索词]

# 默认搜索 "小王"
luajit tests/test_contacts_search.lua "张三"
```

### 8. test_first_column.lua — 第一列图标点击

从顶部开始，依次点击第一列7个图标。

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

```bash
luajit tests/test_search.lua [搜索词]

# 默认搜索 "小王"
luajit tests/test_search.lua "张三"
```

流程：
1. 获取微信窗口位置
2. 搜索框在 (窗口x+180, 窗口y+50)
3. 点击搜索框 → 粘贴关键词 → 回车搜索

---

## 文件说明

```
tests/
├── TEST.md                 ← 本文档
├── test_3columns.lua       ← 三列结构测试
├── test_icons.lua          ← 全窗口图标测试
├── test_third_icons.lua    ← 第三列图标测试
├── test_send_file.lua      ← 发送文件测试
├── test_screenshot.lua     ← 截图发送测试
├── test_search.lua         ← 搜索联系人测试
├── mark_columns.py         ← 三列标注图生成
├── find_icons.py           ← 全窗口图标检测
└── find_third_icons.py     ← 第三列图标检测
```

## 快速验证

```bash
# 一键跑所有测试
cd /opt/my-agent/wechat-ocr
bash run.sh  # 先启动环境

luajit tests/test_3columns.lua
luajit tests/test_icons.lua
luajit tests/test_third_icons.lua
luajit tests/test_send_file.lua
luajit tests/test_screenshot.lua
```
