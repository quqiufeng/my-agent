# 全自动测试与 AI 闭环修复（含 UI 视觉验证）

目标：**人类只描述需求和问题，AI agent 自主定位、修改、验证**。
agent 不只能跑单元测试，还能**按键、发命令、读状态、读屏文本、看真实渲染出来的界面**。

---

## 1. 能力总览

| 能力 | 接口 | 说明 |
|---|---|---|
| 模拟按键 | `kui tap nextpage` / `tap("up")` | 走与硬件相同的 `on_code` 路径 |
| 文本指令 | `kui say "下一页"` / `echo 下一页 > /tmp/ui_say` | 语音/无障碍/远程，ASR 文本直接可用 |
| 读状态 | `kui state` / `ui_info()` | mode/page/npages/pct/size/book/sel/item… |
| 读屏文本 | `kui dump` / `ui_dump()` | 直接读 label，**无需 OCR** |
| 抓屏 | `kui shot a.png` / `/tmp/ui_frame.png` | 824×1200 正向灰度 PNG |
| 看界面 | agent 直接读取该 PNG | 视觉理解布局/字号/留白/错误 |
| 执行过程 | `/mnt/us/ui/events` | `log/click/open/say/luaerr` 时间线 |

**同步保证**：每条命令执行完 `seq` 自增并写 `/tmp/ui_seq`，`kui` 轮询它再返回，
所以不依赖固定 sleep，也不会读到旧状态/旧图（`eips` 会阻塞主循环 1~2s）。

---

## 2. 闭环流程

```
人类: "正文右边空太多，字号切大了但字没变大"
        │
        ▼
 agent 读代码 (boot/lua/init.lua)
        │
        ▼
 复现:  kui state / kui say "字号大" / kui shot before.png
        │
        ▼
 看界面: 读 before.png（视觉） + kui dump（文本） + kui state（状态）
        │
        ▼
 定位:  例：body label 字体写死 26，只改了分页参数
        │
        ▼
 修改 init.lua (ui.setfont + 按 ui.measure 重算 maxw/lines)
        │
        ▼
 部署:  scp -> /mnt/us/ui/init.lua ; kui restart
        │
        ▼
 验证:  kui run smoke.lua  (PASS/FAIL)
        kui shot after.png
        imgdiff.py before.png after.png   (视觉回归)
        agent 再读 after.png 确认
        │
        └── 不通过则继续循环
```

---

## 3. 工具

```bash
cd boot/test
./kui state                 # 状态
./kui tap nextpage          # 按键
./kui say "读异类"           # 文本指令
./kui dump                  # 当前屏文本
./kui shot a.png            # 抓屏
./kui run smoke.lua         # 跑测试
./kui eval 'ui.log("hi")'   # 任意 Lua
./kui restart               # 重启（重置字号档位到「中」）
./kui log 30                # 执行过程
```

设备侧原生文本通道（不经 Lua 包装，适合 ASR/远程）：

```bash
ssh kindle 'echo "读三体" > /tmp/ui_say'
ssh kindle 'echo "下一页" > /tmp/ui_say'
```

支持的指令（`init.lua` 的 `cmd()`）：

| 类型 | 例子 |
|---|---|
| 打开书 | `读异类` / `打开三体` / `请打开罗马人的故事` |
| 翻页 | `下一页` / `上一页` / `快进` / `快退` |
| 定位 | `跳到第20页` / `第3章` / `下一章` / `上一章` |
| 菜单 | `目录` / `菜单` / `书架` |
| 字号 | `字号大` / `字号小` / `字号中` |
| 状态 | `进度` / `读到哪` |

---

## 4. 三层验证

1. **状态断言**（最快，不依赖渲染）
   ```lua
   tap("nextpage"); ok(ui_info().page==p+1, "翻页")
   ```
2. **文本断言**（验证真正显示的内容，免 OCR）
   ```lua
   local t = ui_dump(); ok(t:find("第17节",1,true)~=nil, "章节标记可见")
   ```
3. **视觉验证**（布局/字号/留白/乱码，只有看图能发现）
   ```bash
   ./kui shot after.png
   python3 imgdiff.py baseline.png after.png 0.02   # 像素回归
   ```
   再把 `after.png` 交给 agent 的视觉能力直接「看」。

> 建议：状态/文本断言进 `smoke.lua` 做回归；关键界面存 `baseline/*.png` 做视觉回归。

---

## 5. AI 如何「看」界面

`/tmp/ui_frame.png` 就是喂给 `eips` 的那张图：**824×1200、正向、灰度，不需要旋转**。
agent 直接读取该文件即可看到：标题、字号、行距、左右/底部留白、标点、页脚、残影。

判定优先级：

- **结构化优先**：位置/页码/状态用 `kui state`，文字用 `kui dump`（100% 准确）。
- **视觉兜底**：排版、留白、字体粗细、乱码、元素重叠等只能看图。
- 两者交叉验证，避免「文本对但布局错」。

---

## 6. 真实闭环案例（本次修复）

**人类**：「内容区右侧空这么多？」「字体颜色也太浅了」「底部状态栏离边缘太远」

```bash
# 复现并量化
./kui say "字号大"; ./kui shot big.png
python3 - <<'PY'
from PIL import Image; import numpy as np
im=np.array(Image.open('big.png').convert('L'))[194:1078,:]
c=np.where((im<128).any(axis=0))[0]; print("右留白", 823-c.max())
PY
# -> 右留白 218px（异常）

./kui dump | head -3        # 文本正常
./kui state                 # size=大，但 npages 与「中」一样 → 字号没生效
```

**定位**：`init.lua` 里 `W.r_body = mk("",46,194,26)` 字体写死 26，
切字号只改了 `maxw/lines`，没改字体 → 「大」是 26px 文本按 21 字/行分页。

**修复**：`paginate()` 里 `ui.setfont(W.r_body, sz.fs)`，并用 `ui.measure` 实算 `maxw/lines`；
C 侧给刷新加 gamma 1.8 压暗抗锯齿；页脚/分隔线下移。

**验证**：
```
右留白 218px → 81px；页数 89/96/160 三档真正不同
kui run smoke.lua -> pass=25 fail=0
```
全程 agent 自己看图 + 读状态完成，人只给了三句自然语言。

---

## 7. 让 agent 自主修复的提示词模板

> 设备是 Kindle 电纸书，界面层在 `boot/lua/init.lua`，工具在 `boot/test/kui`。
> 需求：<一句话>。
> 请：1) 复现并用 `kui state/dump/shot` 取证；2) 读截图确认视觉问题；
> 3) 改 `boot/lua`（必要时 `boot/src` 并 `sh build.sh`）；
> 4) `scp` 部署 + `kui restart`；5) 跑 `kui run smoke.lua` 并再看一次截图；
> 6) 回归通过后更新文档。不要问我实现细节，直到需要产品取舍时再问。

---

## 8. 注意事项

1. **命令有副作用**：测试会真实翻页并写进度 `pos.lua`、可能改字号；
   `kui restart` 可把字号重置为「中」。批量测试前可先备份 `pos.lua`。
2. **同步用 `seq`**：不要用固定 sleep 等 `eips`（它阻塞 1~2s）。
3. **`smoke.lua` 要按名称找菜单项**，不要假设位置（有无「目录」项会变）。
4. **视觉回归阈值**：e-ink 有轻微灰阶抖动，建议 `imgdiff.py` 阈值 0.01~0.02。
5. **抓图前先 `ui.flush()`**（`kui shot` 已内置），否则可能抓到上一帧。
6. **C 改动必须重编**：`cd boot/src && sh build.sh`，产物 `lvgui` scp 到 `/mnt/us/lvgui`。
