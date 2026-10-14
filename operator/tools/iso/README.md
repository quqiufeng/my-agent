# iso — 等距解释图 / 动画（native：Dart + Lua）

把"零件"拼成 **等距(isometric)解释图**，渲染成 **PNG** 或 **GIF/MP4**（动画）→ 发微信。
**引擎已从原项目的 JS(kit) 全量移植为 Dart 与 Lua 两份等价实现，无 Chrome、无 node。**

---

## 用法

```bash
operator/tools/iso_native.sh render tmall-genie [--ss 2] [--lift 0..1] [--theme dark|light] [--out 目录] [--to 会话] [--no-send]
operator/tools/iso_native.sh anim   tmall-genie [--motion] [--frames 120] [--ss 2] [--out 目录] [--to 会话] [--no-send]
```

- 走 Flutter app（`~/iso_flutter/app`）的**离屏渲染**：`ISO_EXPORT`/`ISO_FRAME`/`ISO_N`/`ISO_MOTION`/`ISO_THEME`/`ISO_SS`/`ISO_OUT`。
- `anim` 在**一次进程内**渲染所有帧（`ISO_BATCH`）→ ffmpeg 合成 GIF/MP4。120 帧 ≈ 19s。
- **图名**（见 `~/iso_flutter/iso_engine/lib/main.dart` 的 `_figures`）：
  - `tmall-genie` —— 天猫精灵（**Lua** 定义：`lib/lua/figures/tmall_genie.lua`，默认）
  - `tmall-genie-dart` —— 天猫精灵（**Dart** 参考实现：`main.dart` 的 `tmallGenieDartFigure`，与 Lua 版**逐像素一致**，RMSE≈1e-5）
  - `lathe` / `tube` —— 引擎测试图（Dart）
- 改图/加图后需 `cd ~/iso_flutter/app && flutter build linux --release`。

---

## 引擎：Dart 与 Lua 并存

| | 位置 | 说明 |
|---|---|---|
| **Dart** | `~/iso_flutter/iso_engine/lib/iso_kit.dart` / `iso_lathe.dart` / `iso_tube.dart` | `iso-kit`/`lathe`/`tube` 的 Dart 移植（全量） |
| **Lua** | `~/iso_flutter/iso_engine/lib/lua/{iso_kit,lathe,tube}.lua` | 同上的 Lua 移植（全量） |
| **桥** | `~/iso_flutter/iso_engine/lib/lua_bridge.dart` | Dart `dart:ffi` 加载 `libluajit-5.1.so.2`，跑 Lua、取回路径串/JSON |
| **渲染层** | `~/iso_flutter/iso_engine/lib/iso_render.dart` | kit 的线稿样式 → Canvas（**两份共用**） |

- **图**可**用 Dart 写**或**用 Lua 写**：Lua 图放 `lib/lua/figures/*.lua`（返回 `function(lift,time) -> 绘制指令 JSON`）。
- **等价性**：同图 Dart 与 Lua 输出**逐字符相同**（`tool/kit_parity.dart` ↔ `lib/lua/kit_parity.lua`）；渲染结果 RMSE≈0.001%。

---

## 技术原理（native 版）

1. **等距投影**：世界点 `[x,y,z]` 投到 2D —— 方位角 **45°**、俯仰角 **30°**（`iso()`）。
2. **实心体 + 四色明暗**：实体=地面轮廓向上挤出（`slabOf` 盒 / `cylinder` 柱 / `lathe` 回转体 / `tube` 管道）；每个可见面按法向分 **4 档明暗**（`SHADES=4`），另有 top/crease/outline。
3. **Painter's order**：`depthOf = 点·视线`，从远到近画。
4. **风格 = 单色线稿**：实体填充=卡片底色、面=贴近底色的 4 档阴影、边=细线（`hi/mid/lo/faint` 色阶）、`halo`=blur 软投影。**light 主题**（白机身/浅底/深灰细边）才是"产品图"那版。

---

## 设计规范

写图（无论 Dart 还是 Lua）请照 **`anatomy/references/*.md`**：`craft`（构图/明暗/零件）、`kit`（API）、`motion`（缓动/弹簧/一次性事件）、`verify`/`webgl`/`3d`。

---

## 历史 / 署名

- 本工具的绘图引擎原为开源项目 **anatomy** 的 JS 库（`kit/iso-kit.mjs`/`lathe.mjs`/`tube.mjs`）+ node + resvg 链路（`iso.sh`，**已退役删除**）。
- 现已**全量移植为 Dart 与 Lua**（见上），JS 不再使用；本目录仅保留其 **`references/`（设计规范）** 与 **`LICENSE`**。
- **https://github.com/wheresryan22/anatomy** （MIT License © 2026 Ryan · @wheresryan22）—— 特此致谢作者。许可见 `anatomy/LICENSE`，**请勿删除署名**（Dart/Lua 移植文件头均带此署名）。
