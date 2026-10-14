# iso — 等距解释图 / 动画

`operator/tools/iso.sh`：把"零件"拼成**等距(isometric)解释图**，渲染成 **PNG**（快，resvg，免浏览器）或 **GIF/MP4**（动画）→ 发微信。

## 用法
```
tools/iso.sh render <build.mjs | 样例名> [--theme dark|light] [--page] [--out 目录] [--to 会话] [--no-send] [--zoom N]
tools/iso.sh anim   <build.mjs | 样例名> [--frames N] [--theme ..] [--out 目录] [--to 会话] [--no-send]
```
- `render`：默认出**纯图**（resvg，~0.5s）；`--page` 出**整页卡片**（Chrome，含标题/提示/实时读数/活内容，~3.5s）。
- `anim`：逐帧重建运动件（读环境 `ISO_FRAME`/`ISO_N`）→ resvg 出帧 → ffmpeg 合成 **GIF + MP4**。

## 目录
| 路径 | 说明 |
|------|------|
| `iso.sh` | 工具（render / anim） |
| `anatomy/kit/` | 绘图库：等距相机、实心体(盒/柱/回转体)、管道、平滑着色、SVG 渲染 |
| `anatomy/scripts/` | `inline-kit.mjs` / `capture.mjs`（`--page` 用） |
| `anatomy/references/*.md` | **最佳实践**（写 `build.mjs` 时遵守）：`craft`(构图/明暗/零件库) `kit`(API) `motion`(运动) `webgl`/`verify`/`3d` … |
| `anatomy/examples/tmall-genie/build.mjs` | 示例：**天猫精灵 X1 智能音箱** |

## 中文说明 & 仓耳字体
每张图建议在**底部加一句中文说明**（"这是什么东西"）。写在 `build.mjs` 的 body 里，例如：
```js
`<text x="${WIDTH/2}" y="${HEIGHT-72}" text-anchor="middle"
       font-family="TsangerJinKai02, 仓耳今楷02" font-size="27"
       fill="var(--anatomy-text)">天猫精灵 X1 智能音箱</text>`
```
- **字体**：本机已装 **仓耳今楷02**（`~/.local/share/fonts/TsangerJinKai/TsangerJinKai02-W05.ttf`，fontconfig 已识别）；`font-family="TsangerJinKai02, 仓耳今楷02"` 即可，**resvg 光栅时会自动取到**，无需额外配置。
- **位置**：`y = HEIGHT - 72`（离底 ~72px）为推荐；要保证图与文字不重叠，`fitProjection` 用**比 SVG 矮一截**的高度（示例：`FIGH = 560`，`HEIGHT = 660`）。
- **颜色**：用 `fill="var(--anatomy-text)"` 随主题走（我们的解析步骤会把 `var()` 换成实际色）。

## 参考与致谢
本工具的绘图库（`anatomy/kit/`）与最佳实践文档（`anatomy/references/`）来自开源项目 **anatomy**：

- **https://github.com/wheresryan22/anatomy**  （MIT License © 2026 Ryan · @wheresryan22）

特此致谢作者。原许可见 `anatomy/LICENSE`，请勿删除。
