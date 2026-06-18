# WeChat OCR 测试脚本

## 环境要求

```bash
export LD_LIBRARY_PATH=./lib:/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib
export LUA_PATH="/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;;"
export LUA_CPATH="/usr/local/lualib/?.so;;"
```

## 测试脚本

### 1. test_3columns.lua — 三列结构检测

检测微信窗口的三列结构（图标栏 / 列表区 / 内容区），用时间戳定位第三列边界。

```bash
luajit tests/test_3columns.lua
```

| 输出 | 说明 |
|------|------|
| 控制台 | 三列分界位置（px和百分比），第三列识别文字 |
| ~/wechat_3cols_test.png | 标注图，蓝红线标三列分界 |

依赖：`tests/mark_columns.py`（Pillow 标注，支持中文）

---

### 2. test_icons.lua — 全窗口小图标检测

扫描整个微信窗口，用多阈值二值化找方形暗色块（过滤文字），标注所有小图标。

```bash
luajit tests/test_icons.lua
```

| 输出 | 说明 |
|------|------|
| 控制台 | 找到的图标总数 |
| ~/wechat_icons.png | 标注图，全窗口图标编号标注 |

依赖：`tests/find_icons.py`

---

### 3. test_third_icons.lua — 第三列小图标检测

先 OCR 定位第三列 → 限制输入框上方 250px → 扫描找小图标 → 标注。

```bash
luajit tests/test_third_icons.lua
```

| 输出 | 说明 |
|------|------|
| 控制台 | 第三列位置、输入框Y、图标数 |
| ~/wechat_third_icons.png | 标注图，仅第三列底部图标 |

依赖：`tests/find_third_icons.py`

---

## 文件说明

```
tests/
├── TEST.md               ← 本文档
├── test_3columns.lua     ← 三列结构测试
├── test_icons.lua        ← 全窗口图标测试
├── test_third_icons.lua  ← 第三列图标测试
├── mark_columns.py       ← 三列标注图生成（Python）
├── find_icons.py         ← 全窗口图标检测（Python）
└── find_third_icons.py   ← 第三列图标检测（Python）
```
