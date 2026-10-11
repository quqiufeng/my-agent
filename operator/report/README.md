# operator/report — 排版好的日报/简报（Kami 方案）

把 WordCard 的 **Kami 排版方案**迁到这里：暖米纸底 · 单一墨蓝 · 衬线承载层级。
用于生成**排版好的日报/简报/报告**（PNG 或 PDF）。

## 文件

| 文件 | 说明 |
|------|------|
| `kami.css` | Kami 令牌与排版样式（`--parchment/--brand/--serif`…） |
| `daily-report.html` | 日报模板（页眉 + 导语 + 指标 + 要点 + 表格 + 页脚） |
| `render.sh` | 用 headless Chrome 渲染 HTML → PNG/PDF |
| `TYPOGRAPHY.md` | 完整规范（令牌/字体/字号/间距/减法原则） |

## 用法

```bash
# 1) 改内容：编辑 daily-report.html（或由脚本填充）
# 2) 出图：
operator/report/render.sh operator/report/daily-report.html /tmp/daily.png
#   或出 PDF：
operator/report/render.sh operator/report/daily-report.html /tmp/daily.pdf
```

字体：`TsangerJinKai02`（仓耳今楷，个人免费）已安装于 `~/.local/share/fonts/kami/`；
等宽用 `Maple Mono NF CN`。若换机需先装这两套字体。

## 后续（生成器）

可仿 `tools/dash_html.lua` 的方式写一个 `daily_report.lua`：把数据（任务/统计/热门仓库…）
填进 Kami 模板 → `render.sh` 出图 → 发微信。届时再加 `operator/tools/report.sh` 白名单工具。

> 规范出处：tw93/Kami（MIT）。细则见 `TYPOGRAPHY.md`。
