# my-agent 全自动化开发模式（Fully-Automated Mode）

> Agent 能**看见并使用自己创造的软件**，在“被使用中”直接迭代验证。
> 这是软件行业的**新模式**：代码第一次由创造它的 Agent 在**真实运行、真实交互**中闭环迭代。
> 本文档与 `agentkit/README.md`、根 `AGENTS.md` 配套；模式源自 WordCard，见其 `automation.md`。
> 文档版本: v1.0 — 2026-10-11

---

## 一、这是什么

传统开发闭环是**单向**的：

```
人写代码 → 单元测试/CI → 打包 → 人做 UI 验收 → 反馈 → 人再改
           （机器看不见界面，也“用不了”成品）
```

本模式把它变成 **Agent 自闭环**：

```
Agent 设计 → 构建 → 在真实会话里运行 → 用 API/FFI 模拟人操作 UI
     ▲                                              │
     │                                              ▼
     └── 改代码 ← 定位问题 ← 读图自检 ← 截图（只截目标窗口）
```

关键点：Agent 既**能操作**成品（点击/输入/翻页/发送），也**能看见**成品（截图 + 读图 + OCR），
于是可在**真实使用**中发现问题并立即修复、复验——无需人类中转描述。

> 一句话：**代码第一次可以直接在“使用中”被迭代验证。**

---

## 二、为什么它是新的

| 维度 | 传统（含 AI 编码助手） | 本模式 |
|------|------------------------|--------|
| 验证对象 | 源码 / 单元测试 | **真实运行的应用/界面** |
| 谁看界面 | 人 | **Agent 自己看（截图 + 读图 + OCR）** |
| 谁操作 | 人点鼠标 | **Agent 用 API/FFI/XTest 模拟操作** |
| 反馈信号 | 日志/断言 | **像素级真实渲染 + 交互状态** |
| 迭代速度 | 分钟~小时（人参与） | **秒~分钟（全自动）** |
| 人参与 | 必须 | **可选（只在关键决策时）** |

---

## 三、能力边界（已实现）

1. **构建**：C++ / Lua / 编译各子模块（见“常用命令”）。
2. **运行**：一律**在图形会话内**启动（继承 `DISPLAY`/`XAUTHORITY`）。*勿用 systemd 服务启动 UI*。
3. **操作（驱动）**：
   - `agentkit`（LuaJIT + FFI）：窗口定位、区域 OCR、区域锚定点击、剪贴板输入、模板匹配；
   - 应用适配器：`ak.app("wechat")` / `ak.app("chrome")` / `ak.app("wordcard")`；
   - 白名单工具：`operator/tools/*.sh`（大脑可执行的能力边界）。
4. **看见（视觉自检）**：`agentkit/bin/shot.sh`（GL 窗口 root 抓取+裁剪）→ **`Read` 读图** +
   `agentkit.ocr`（PP-OCRv4）取文字与坐标。
5. **迭代**：定位差异 → 改代码 → 重新构建/运行 → 再截图验证 → 记录到映射/脚本 → 提交。

> **控件映射思想**：每个按钮/图标只需**探索一次**，把窗口相对区域固化进 `agentkit/maps/<app>.lua`；
> 之后所有操作按名字点击（`m:click("rail_chat")`），窗口移动/缩放不失效。工作流则写成 Lua 脚本复用。

---

## 四、使能技术栈

| 环节 | 技术 | 位置 |
|------|------|------|
| 窗口/输入 | xdotool + libagentkit.so（XTest, C++） | `agentkit/{x11.lua,cpp/}` |
| 截屏 | ImageMagick（root 抓取 + 裁剪） | `agentkit/bin/shot.sh` |
| OCR | PP-OCRv4（C++ 库，LuaJIT FFI） | `agentkit/ocr.lua` → `libocr_simple.so` |
| 模板匹配/差分 | OpenCV | `agentkit/cpp/agentkit.cpp` |
| 语音识别 ASR | SenseVoice.cpp | `agentkit/voice.lua` → `voice/listen*` |
| 语音合成 TTS | sherpa-onnx + Kokoro | `agentkit/voice.lua` → `voice/say.sh` |
| 输入法切换 | IBus（`ibus engine`） | `agentkit/x11.lua` `ime_en/ime_zh` |
| 微信 | wechat_robot.lua + 映射 | `agentkit/adapters/wechat.lua`、`wechat-ocr/` |
| Chrome | xdotool + 映射 | `agentkit/adapters/chrome.lua` |
| 大脑能力 | 白名单工具 | `operator/tools/*.sh` |

---

## 五、对外 API（供 Agent / 语音 / 微信 驱动）

Lua（统一入口，需 `package.path`）：

```lua
package.path = "/opt/my-agent/?.lua;/opt/my-agent/?/init.lua;" .. package.path
local ak = require("agentkit")

-- 窗口 + OCR + 区域锚定点击
local w = ak.x11.window("WordCard", { exact = true }); w:activate()
for _, b in ipairs(w:ocr()) do print(b.gx, b.gy, b.text) end
w:click_text("导入", { 0, 0, 180, 720 })        -- 找不到自动重试

-- 控件映射（一次探索，名字点击）
local m = ak.map("wechat")
m:click("rail_chat"); m:type("input_box", "你好"); m:ocr("message_area")

-- 应用适配器
local wx = ak.app("wechat"); wx.open_chat("文件传输助手"); wx.send("你好")
local ch = ak.app("chrome"); ch.goto("example.com"); print(ch.title())

-- 语音
local wav = ak.voice.tts("你好，我是星期五"); print(ak.voice.asr(wav))
```

大脑侧仍是**白名单**：任何“能执行的操作”都必须是一个 `operator/tools/*.sh`（见根 `AGENTS.md`）。

---

## 六、标准闭环（可复制）

```bash
# 1) 构建（按改动范围）
make -C /opt/my-agent/agentkit/cpp            # libagentkit.so
chmod +x /opt/my-agent/agentkit/bin/shot.sh
make -C /opt/my-agent/voice/listen            # 语音监听（如改）
# 微信 C 核心（如改）：cmake -S wechat-ocr -B wechat-ocr/build_lib ... --target wechat_ocr_core

# 2) 会话内运行（GUI/语音等）
P=$(pgrep -x pcmanfm-qt|head -1); XA=$(tr '\0' '\n' </proc/$P/environ|sed -n 's/^XAUTHORITY=//p')
export DISPLAY=:0 XAUTHORITY="$XA"

# 3) 驱动（Lua 脚本 / agentkit）
luajit -e 'package.path="/opt/my-agent/?.lua;/opt/my-agent/?/init.lua;"..package.path
  local ak=require("agentkit"); local wx=ak.app("wechat"); wx.send("自测")'

# 4) 看见：置顶目标窗口 → 区域抓图 → Read 读图
/opt/my-agent/agentkit/bin/shot.sh 0 0 2560 1408 /tmp/opencode/ui.png
#   5) 读图判差异 → 改代码 → 回到 1) / 更新 maps
```

---

## 七、已实证案例（本仓库）

一次全自动自测（无人参与）：
1. 用 `agentkit` 定位微信窗口（xdotool），`shot.sh` 截图 + `Read` 读图，PP-OCR 取控件文本。
2. 探索左侧功能栏：**像素行暗度分析**定位图标中心 → 逐个点击 + OCR 结果页标题**判定功能名**
   （聊天/通讯录/收藏/朋友圈/视频号/搜一搜/小程序），写入 `maps/wechat.lua`。
3. `wx.open_chat("文件传输助手")` + `wx.send("agentkit v1 已就绪 OK")` → 绿气泡出现、会话预览同步。
4. Chrome：`ch.goto("example.com")` → 标题 `Example Domain`，页面 OCR 正确。
5. 期间发现并修复：**输入法默认中文**导致英文被转换 → `ime_en/zh` + **剪贴板粘贴**绕过 IME；
   `xclip` 后台持选区导致管道挂起 → 重定向后台；GL 窗口截图改走 `shot.sh`。

---

## 八、局限与后续

- **视觉判读**仍需多模态读图；复杂动画/瞬时态需多帧采样。
- 依赖桌面会话环境（`XAUTHORITY`/GL/IBus）；无头环境需虚拟显示（Xvfb + 软件 GL）。
- 朋友圈等为**独立顶层窗口**、搜一搜为**全屏内嵌视图**，工作流需处理窗口/视图切换。
- 后续：加**流程录制器**（`ak.record()` 包裹 click/type，跑完 `:save("flows/x.lua")` 生成带校验的可回放脚本）；
  给映射做可视化标定；把标准闭环固化进 `operator/TESTING.md` 回归。

---

## 九、相关文档

- `agentkit/README.md` — 库用法、映射格式、输入法、截图。
- 根 `AGENTS.md` — 项目结构、白名单契约、常用命令、自主测试。
- `operator/TESTING.md` — 测试项清单 + 回归流程。

---

## 十、附：对 Codex / Computer Use 实现方案的解析

> 目的：把“通用 Computer Use”与本项目做法对照，说明我们为何选择
> **“探索一次 → 固化映射 → 脚本化”** 这条路线。

### 1) 通用回路：感知—推理—行动

逐步循环：**截屏 → 送入多模态模型 → 输出动作 → 执行 → 再截屏观察**，直到完成。
OpenAI 的 CUA/Operator、Anthropic 的 computer-use（`computer` 工具），以及 Codex 的
“操作电脑/浏览器”能力，都是这一范式。模型看到的是**图像**，回的是**动作**。

### 2) 动作空间（典型）

`screenshot`、`mouse_move(x,y)`、`left_click`/`right_click`/`double_click`、
`left_click_drag`、`type(text)`、`key(combo)`、`scroll(dx,dy)`、`wait`、`cursor_position`。

### 3) 坐标落地（核心难点）

- 模型多在**归一化坐标**（0–1000，或相对 1024×768 视口）输出点击点，harness 再映射到真实分辨率。
- 更稳的实现会结合**可访问性树 / AXTree / DOM** 给元素命名与包围盒，减少“纯像素猜坐标”的误差。
- 误差来源：DPR/缩放、多显示器、窗口装饰与 reparent、动画/加载延迟。

### 4) Harness（框架）

组装消息（截图 + 历史动作）→ 调模型 → 解析动作（tool call / JSON）→ 分发到驱动层
（XTest / CDP / ADB / 系统 API）→ 回传结果与**新的截图**，循环下去。
一般运行在**隔离环境**（VM/容器/浏览器沙箱），便于失败回滚与快照。

### 5) 与本项目对照：从“解释执行”到“编译”

| 维度 | 通用 Computer Use | agentkit（本项目） |
|------|-------------------|--------------------|
| 感知频率 | 每步都要截图 + VLM 推理 | **探索一次**，此后主要靠映射 |
| 坐标 | 模型现场输出 / 归一化 | **窗口相对固定区域**（`maps/*.lua`） |
| 稳定性 | 依赖模型每一步都对 | 区域锚定 + OCR/模板校验 + 重试 |
| 成本 | 每步一次多模态推理（贵/慢） | 命中映射时**零推理**，仅 OCR 校验 |
| 工作流 | 交给人/模型即兴决策 | **固化为 Lua 脚本**，可 diff、可回归 |

> 一句话：通用 Computer Use 是**解释执行**（每步现场理解）；agentkit 把它**编译**为
> 「静态锚点(map) + 动态脚本(flows)」，**推理只发生在探索期**。

### 6) 绕不开的工程坑（本项目已解）

- **输入法**：非英文环境需切 IME，或用**剪贴板粘贴**绕过（`ime_en/ime_zh`、`xclip`）。
- **窗口**：WM reparent/最大化会改变几何与坐标；**GL 窗口**不能被 `import -window` 直接抓，
  需 root 抓取 + 裁剪（`shot.sh`）。
- **时序**：动画/加载需等待；**合成鼠标移动可能不触发 hover tooltip**（故用“点击后 OCR 结果页”判定）。
- **校验**：点击后必须复核（OCR 文本变化 / 图像差分 `ak_diff`）。

### 7) 结论

通用回路（看图→动作→复验）**必要但昂贵**；对**重复出现的固定界面**，用
“探索一次 → 固化区域 → 脚本化”把每步推理**摊销**掉，是更稳、更快、更可维护的落地形态。
这正是 agentkit 的核心主张：**把 Computer Use 编译下来**。


---

## 附二：四个核心技术与探索流程

> 这套方案的落地由四块拼成：**视觉识别 → 位置缓存 → 动态代码生成 → 流程回放**，
> 而**探索**是把它们串起来的一次性前置动作。

### 1) 视觉识别（Visual Recognition）

- **截图**：`agentkit/bin/shot.sh`（GL 窗口 root 抓取 + 裁剪）。
- **OCR**：PP-OCRv4（`agentkit.ocr`）取文本 + 像素坐标。
- **模板匹配**：OpenCV `ak_match` 识别**无文字图标**；图像差分 `ak_diff` 判断状态变化。
- 用途：**探索期发现**控件/文字/图标；**运行期校验**操作是否生效。

### 2) 位置缓存（Position Caching）

- 控件以**窗口相对区域**缓存于 `maps/<app>.lua`：`{ x, y, w, h, text?, icon? }`。
- **一次探索，长期复用**；窗口移动/缩放不影响（相对坐标锚定）。
- 命中缓存时**零推理**：`m:click("rail_chat")` 直接点到区域中心。
- 维护：界面变化时**增量更新**（重新 `m:learn(name,...):save()`），不必全量重探。

### 3) 动态代码生成（Dynamic Code Generation）

- 把探索结果与工作流**生成可执行的 Lua 代码**，而非不可读的录制轨迹。
- 代码是**一等产物**：可读、可改、可 diff、可版本化、可跨应用复用。
- 例：`local m = ak.map("wechat"); m:click("rail_chat"); m:type("input_box", "你好")`；
  或将一次探索/一趟流程落成 `flows/xxx.lua`。

### 4) 流程回放（Workflow Replay）

- 回放 = 按脚本逐步执行，每步：**定位（缓存区域）→ 动作（点击/输入）→ 校验（OCR/差分）→ 失败重试**。
- 确定性来源：静态锚点 + 校验 + 重试 ⇒ 可**无人值守**重复运行。
- 校验方式：操作后 OCR 目标区域文本是否变化、或 `ak_diff` 图像差分是否超阈值。

### 5) 探索流程（一次性前置）

1. **定位窗口**：xdotool 按精确标题 / WM_CLASS 找到窗口并取几何。
2. **视觉识别**：截图 + 读图 / OCR，识别界面结构；图标用像素行暗度分析或模板匹配。
3. **交互验证**：点击候选控件 → OCR 结果页标题**判定功能** → 记录其窗口相对区域。
4. **固化**：写入 `maps/<app>.lua`；把走通的步骤写成流程脚本（动态代码）。
5. **之后只跑脚本**，不再探索；界面变动时回到 2) 做**增量**更新。

### 6) 四者关系

```
视觉识别 ──(探索期)──▶ 位置缓存(map) ──▶ 动态代码(脚本) ──▶ 流程回放
    ▲                                                          │
    └──────────── 运行期校验（OCR / 图像差分）◀───────────────┘
```

> 本质：**探索期用视觉识别建立缓存**，**运行期用缓存回放动态脚本**；
> 视觉只在“探索”与“校验”两端出现，中间过程零推理、确定性执行——这正是把
> Computer Use “编译”下来的具体做法。

---

## 附三：开发过程即高质量训练语料（带视觉 + 自验证）

> 本模式把“开发过程”本身变成**可训练的数据**：边做边攒，自产自验。
> 说明：当前项目**不训练自有模型**；此处只描述其潜在价值与记录规范，备将来使用。

### 1) 为什么质量高

1. **标签自验证**：每个动作后置校验（OCR / 图像差分）给出成败信号 → **自动 reward**，
   无需人工标注（RLVR 思路），可直接用于拒绝采样 / RL。
2. **三层信号同源**（极难得）：
   - 感知层：`screenshot → 控件（坐标/区域）` —— 教“看懂界面”；
   - 决策层：`任务 → 子目标序列` —— 教“规划”；
   - 合成层：`任务 → 可执行代码（Lua）`，且**回放器即单元测试** —— 教“程序合成”。
   一份数据同时喂视觉 / 行为 / 代码。
3. **自增长飞轮**：探索 → 映射 → 脚本 → 回放校验 → 产出更多带标签轨迹。
   数据不是“采”来的，是“**长**”出来的，且覆盖长尾真应用（微信 / Gemini / 中文 UI / 输入法坑）。

### 2) 要成为可用语料，先解决三件事

- **噪声**：OCR 错字、区域粗、坐标抖动 → 只采“**校验通过**”的轨迹，或用 reward 过滤清洗。
- **分布与隐私**：单机 / 单分辨率 / 少数 app；截图可能夹带**密钥与私聊** → 必须**脱敏**后再存。
- **结构化 schema**（否则是脏数据）：

  ```
  { task,
    obs: { screenshot, ocr | a11y, ts },
    thought?, action,
    verify: { ok, evidence },
    reward,
    artifact: <lua 脚本 / 映射> }
  ```

### 3) 落地

- `agentkit/batch`、`agentkit/record` 可增加**可选 trace 记录**：每步落
  `截图 + 动作 + 校验结果 + reward + 生成的脚本`（默认**脱敏**、可关闭）。
- 这样“开发过程”本身即在一份**带视觉、自验证、多模态**的数据集上持续积累，需要时即可取用。

---

## 附四：学习即产物 · 双层学习

> 附三说“开发过程是语料”；本附更进一步：**“学习”不等于“改权重”**——
> 本模式**已经在学习**，只是学到**外部产物**，而非权重里。

### 1) 现在就在学，只是学到产物里

- 探索一次 → 掌握：映射（位置缓存）、脚本（工作流）、记忆。
- 这种“掌握”的性质：**可读、可 diff、可回滚、可跨机迁移、不灾难性遗忘**。
  对工具型 Agent，常比改权重更划算、更可信。
- 附三所记的轨迹 `(obs, action, verify, reward, artifact)`，正是将来在线学习所需的**经验流**。

### 2) 两套时间尺度的学习

| | 快回路 | 慢回路 |
|------|--------|--------|
| 载体 | 上下文 / 外部产物 / 记忆 | 模型权重 |
| 成本 | 低、分钟级 | 高、离线 |
| 特性 | 即时、可审计、可回滚 | 泛化强，但易污染 / 遗忘 |

本模式是**快回路的极致**：边探索边掌握，无需等下线的训练。

### 3) 在线权重学习的三个硬门槛

1. **无遗忘**（稳定性-可塑性）；
2. **可信的信用分配**；
3. **可回滚 / 可审计**。

工具型 Agent 出错必须能一键退回，而权重里的“掌握”**退不回去**。因此即便在线学习成熟，
**“代码 / 映射”这层仍会作为确定性的安全网长期存在**。

### 4) 结论：双层学习

> 权重学“怎么想”，产物学“怎么做”；**探索现场**就把“怎么做”固化下来，不必等下线训练。

这比“先训练再部署”更先进：学到的东西**当场可用、可验证、可回退**。

---

## 附五：效率来源、适用前提与边界

> 把本模式从“方法”讲成“**什么时候值得用**”。

### 1) 效率来源

- Agent 从“写代码的人”变成“**拥有整个特性的人**”：设计 → 构建 → 运行 → 操作 →
  看图验证 → 迭代，**全程无需人转述**。
- 省掉的最大损耗，是“人做 UI 验收 → 口述问题 → 人再改”这一段。
- 人上移到**定目标 / 定验收**层。

### 2) 三个前提（缺一打折）

1. **可被操作的接口**：有控制面（`call()` / `state()`）最省；没有就用像素兜底
   （agentkit），但成本与脆性高一档。
2. **可被观测的结果**：能截图、能读状态。纯后端 / 无 UI 的逻辑，优势回落到普通单测。
3. **可判定的对错**：能自验证（文本 / 状态 / 图像差分）的自动化程度最高；
   而**审美、产品取舍、模糊需求**仍需人拍板。

### 3) 边界

- **大面积自动化**：能自验证的**界面 / 交互 / 集成**类功能。
- **仍归人**：**产品判断与品味**。

> 结论：这一边界，已足以改变开发的组织方式——人负责“做什么、好不好”，
> Agent 负责“做完并证明它对了”。

---

*最后更新: 2026-10-11*
