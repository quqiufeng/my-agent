# 传统配色（PALETTE.md）

> 大屏与统一界面（`voice/app`）的点阵主题用**中国传统色**配色。
> 色名/HEX 取自 [nevertoday/zhongguo-traditional-colors](https://github.com/nevertoday/zhongguo-traditional-colors)（742 色，MIT License）。
> 点阵组件风格来自 [karminski-design-skills](https://github.com/karminski/karminski-design-skills)（CC BY-NC-SA 4.0，见 `tools/dotkit/NOTICE.md`）。

---

## 当前采用：霜地 · 墨色 · 黛蓝（浅色）

`dash.sh`（`dash_html.lua`，竖版 820×1380）与 `voice/app`（`dotui.h`）现用此套。

| 角色 | 色名 | HEX | 说明 |
|------|------|-----|------|
| 背景·顶（光晕） | 霜地亮 | `#F4FAE9` | 左上径向光晕 |
| 背景·底 | 霜地 | `#E2F0CB` | 主背景 |
| 卡片·上 | 嫩菊绿 | `#F3F8E8` | 卡片渐变 |
| 卡片·下 | — | `#E7F0D6` | 卡片渐变 |
| 边框 | 姚黄 | `#C4D6A6` | 卡片/胶囊描边 |
| 文字·点（主） | 墨色 | `#1D1B1C` | 标题、点阵、数值 |
| 文字·次 | — | `#5B6B4F` | 说明、单位 |
| 文字·三 | — | `#8A9A7E` | 页脚、次要 |
| 点·未点亮 | — | `#B9CBA0` | 暗点 |
| 点·底纹 | — | `#CBDAB4` | 环外圈 |
| 强调 | 黛蓝 | `#2A3C5C` | 高亮、当前点、分布柱 |
| 警示 | — | `#C77A16` | 阈值 |
| 涨 | 朱砂红 | `#D92121` | 上涨（≥0） |
| 跌 | 青绿 | `#2E8B57` | 下跌（<0） |
| 平 | — | `#5B6B4F` | 持平 |

---

## 备选方案

### D. 黛蓝 · 月白 · 秋香（冷雅暗色）
| 角色 | 色名 | HEX |
|------|------|-----|
| 背景·顶/底 | 黛蓝 / 墨黑 | `#33465F` / `#0F1A20` |
| 卡片 | 苍青 → 苍青(深) | `#1E2A3A` → `#172230` |
| 文字 | 月白 | `#EEF7F2` |
| 强调 | 秋香 | `#C3B787` |
| 涨 / 跌 | 银红 / 松花绿 | `#C74A4D` / `#A0D6B4` |

### A. 苍绿 · 月白 · 秋香（绿调，沉静）
| 角色 | 色名 | HEX |
|------|------|-----|
| 背景·顶/底 | 苍绿 / 云杉绿 | `#223E36` / `#15231B` |
| 卡片 | 绿灰 → 苍绿 | `#314A43` → `#223E36` |
| 边框 | 飞泉绿 | `#497568` |
| 文字 | 月白 | `#EEF7F2` |
| 强调 | 秋香 | `#C3B787` |
| 涨 / 跌 | 银红 / 竹青 | `#C74A4D` / `#00A86B` |

### B. 藕荷 · 月魄（紫调，柔美）
| 角色 | 色名 | HEX |
|------|------|-----|
| 背景·顶/底 | 暮山紫 / 玄黑 | `#6E4D7E` / `#0E100F` |
| 卡片 | 烟紫(暗) → 暗紫 | `#2A2233` → `#1C1626` |
| 边框 | 烟紫 | `#704A70` |
| 文字 | 月魄 | `#E0E7EF` |
| 强调 | 藕荷 | `#EDC3AE` |
| 涨 / 跌 | 银红 / 松花 | `#C74A4D` / `#B6D7A8` |

### C. 缃绮 · 暖（暖金，古朴）
| 角色 | 色名 | HEX |
|------|------|-----|
| 背景·顶/底 | 茶褐 / 墨色 | `#5D3D21` / `#1D1B1C` |
| 卡片 | 古铜褐 → 暗驼棕 | `#3A281B` → `#2A1D13` |
| 边框 | 驼色 | `#66462A` |
| 文字 | 象牙白 | `#FFFEF8` |
| 强调 | 缃绮 | `#F8C471` |
| 涨 / 跌 | 银红 / 松花绿 | `#C74A4D` / `#A0D6B4` |

---

## 应用位置

- **行情大屏**：`operator/tools/dash_html.lua`
  - 覆盖 kit 的 CSS 变量（`:root{ --ink/--accent/… }`）与 `body` 背景；
  - 覆盖 `DotUI.palette`（Canvas 里 accent/warning/critical 是 JS 常量，用 `Object.assign` 在 `DotUI.mount()` 前改）；
  - 涨/跌/平由脚本 `col()` 直接给 HEX。
  - **不改 `tools/dotkit/` 源文件**（遵守 kit 授权：只通过 token 换色）。
- **统一界面**：`voice/app/dotui.h` 调色板（OpenCV 为 **BGR**，注意字节序反转）+ `app.cpp` 光晕色。

> 换方案时，同步改这两处即可；大屏其余布局/组件无需动。

---

## 色卡来源

- **本仓库全表**：[`operator/CHINESE-COLORS.md`](CHINESE-COLORS.md) —— 742 色「名称 — HEX — RGB — 色系」+ 色系统计（由上游 `llms-full.txt` 生成）。
- 上游数据：`llms-full.txt` <https://colors.xiaoxiaodong.ai/llms-full.txt> ／ 主列表 `docs/chinese-color-master-list.md`。
- 官方站点：<https://colors.xiaoxiaodong.ai/>
- 上游许可：GPL-3.0。

---

*文档版本: 1.0 · 创建: 2026-10-07*
