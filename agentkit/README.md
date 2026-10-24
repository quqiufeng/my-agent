# agentkit — 统一 Lua 交互库（LuaJIT + FFI）

把桌面交互的底层能力收敛成**一套 Lua API**，用 `luajit -e` 即可驱动任意 X11 应用
（即使该应用没有对外接口，如微信、Chrome）。核心思想：**区域锚定 + OCR/模板校验 + 前后比对 + 重试**，
窗口移动/缩放不会让点击失效。

## 组件

| 能力 | 实现 | 入口 |
|------|------|------|
| 窗口定位/激活 | **LuaJIT libxdo (`xdo.lua`)**（稳定） | `ak.x11.window(title)` |
| 截屏（含 GL 窗口） | `bin/shot.sh`（root 抓取+裁剪） | `win:capture()` |
| 鼠标/键盘输入 | `libagentkit.so`（XTest） | `win:click()/key()/type()` |
| 文字识别 OCR | `libocr_simple.so`（PP-OCRv4, C++） | `ak.ocr.run(img)` / `win:ocr()` |
| 图标匹配 | `libagentkit.so`（OpenCV） | `win:find_image()` |
| 图像差分 | `libagentkit.so`（OpenCV） | `ak.x11.lib.ak_diff(a,b)` |
| 语音转文字 ASR | SenseVoice.cpp（C++） | `ak.voice.asr(wav)` |
| 文字转语音 TTS | sherpa-onnx + Kokoro（C++） | `ak.voice.tts(text)` |
| 录音 | arecord | `ak.voice.record(sec)` |

## 构建

```bash
make -C /opt/my-agent/agentkit/cpp      # 生成 agentkit/lib/libagentkit.so
chmod +x /opt/my-agent/agentkit/bin/shot.sh
```

## 环境

`luajit` 进程需能连到图形会话；若未设 `DISPLAY`，agentkit 会自动从 `pcmanfm-qt` 会话进程读取
`DISPLAY`/`XAUTHORITY`。首次使用请在脚本里加：

```lua
package.path = "/opt/my-agent/?.lua;/opt/my-agent/?/init.lua;" .. package.path
local ak = require("agentkit")
```

## 快速示例

```lua
-- 1) 定位窗口（标题精确匹配）
local w = ak.x11.window("WordCard", { exact = true })
w:activate()                                   -- 置顶并刷新几何

-- 2) 整体/区域 OCR（返回带“窗口相对坐标”的文本框）
for _, b in ipairs(w:ocr()) do print(b.gx, b.gy, b.text) end

-- 3) 区域锚定点击：在左栏找“导入”并点击，找不到自动重试
w:click_text("导入", { 0, 0, 180, 720 })

-- 4) 找不到文字时也可按图标模板点击
-- w:click_image("/path/icon.png", { thresh = 0.9 })

-- 5) 语音
local wav = ak.voice.tts("你好，我是星期五", { out = "/tmp/a.wav" })
print(ak.voice.asr(wav))                       -- → 文本

-- 6) WordCard 内置接口（有 API 的应用优先用 API）
local stats = ak.app("wordcard").once("stats")
```

## 控件映射（每个按钮/图标一个命名区域）

探索一次后固化为 `maps/<app>.lua`，之后按名字点击即可，无需重复探索：

```lua
local m = ak.map("wechat")          -- 读 maps/wechat.lua
m:click("search_box")               -- 按命名区域中心点击（窗口相对坐标）
m:type("input_box", "你好")         -- 点击并输入（自动切输入法）
m:ocr("message_area")               -- 对区域做 OCR
-- 探索时记录新控件并保存：
m:learn("send_btn", 2415, 1362, 115, 38):save()
```

内置适配器（基于映射）：

```lua
-- 微信
local wx = ak.app("wechat")
wx.open_chat("文件传输助手"); wx.send("你好"); local lines = wx.read()

-- Chrome（JS/CDP）
ak.cdp.goto("https://example.com"); print(ak.cdp.title())
```

## 输入法（IBus）

新打开的应用默认中文，直接输入英文会被 IME 转换。agentkit 在打字前自动切换：

```lua
ak.x11.ime_en()   -- ibus engine xkb:us::eng（默认英文引擎）
ak.x11.ime_zh()   -- ibus engine libpinyin（默认中文引擎）
```

可用 `AGENTKIT_IME_EN` / `AGENTKIT_IME_ZH` 覆盖引擎名。`map:type` / `chrome.goto` /
`wechat.send` 已自动按内容切换（URL/ASCII → 英文，中文 → 拼音）。



```
agentkit/
├── init.lua            -- 统一门面：Window:ocr/find_text/click_text/locate_text、app()
├── x11.lua             -- 窗口(libxdo) + 截屏(sh) + 输入/匹配(FFI libagentkit.so)
├── ocr.lua             -- PP-OCRv4（FFI libocr_simple.so + onnxruntime）
├── voice.lua           -- ASR/TTS/录音（复用 SenseVoice / sherpa-onnx / Kokoro）
├── adapters/
│   ├── generic.lua     -- 任意 X11 应用
│   ├── wordcard.lua    -- 走 WordCard 内置 socket 接口
│   └── wechat.lua      -- 复用 wechat_robot.lua + 窗口定位
├── bin/shot.sh         -- 区域截屏脚本
├── cpp/agentkit.cpp    -- C++ 核心（截屏/输入/匹配/差分/窗口）
└── lib/libagentkit.so
```

## 多分辨率：生成另一套映射

映射按**参考分辨率（本机 2560×1440）**存绝对像素；换分辨率时用脚本**按键位线性缩放**，
另生成一套映射代码（不改运行格式）：

```bash
luajit agentkit/tools/scale_maps.lua <app|all> <WxH> [--ref 2560x1440]
# 例:
luajit agentkit/tools/scale_maps.lua all 1920x1080
#   -> agentkit/maps/<app>.1920x1080.lua
```

- 启用某套：把该套文件「放成」`<app>.lua`（或放到单独目录并设 `AGENTKIT_MAPS`）。
- **注意**：线性缩放只对随分辨率缩放的内容区成立；固定高度的 bars（聊天工具条、浏览器标签栏）
  在换机后仍应靠 OCR 校验/重试（agentkit 已内置）微调。

## 稳定性要点

- **相对坐标**：所有点击以窗口左上角为原点，窗口移动不影响。
- **区域 OCR**：只在目标区域内识别，减少全屏误匹配。
- **重试**：`click_text` 默认重试 3 次，每次间隔可调。
- **校验**：`win:changed(before_png)` 用图像差分判断点击是否生效。
- **精确窗口**：`{ exact = true }` 避免子串命中（如浏览器标签页）。
- 环境变量可覆盖所有路径：`AGENTKIT_LIB` `AGENTKIT_OCR_LIB` `AGENTKIT_ORT`
  `AGENTKIT_OCR_MODELS` `AGENTKIT_SHOT` `SENSEVOICE_BIN` `TTS_OUT` 等。
