# ezviz.md — 萤石/海康监控取流完整流程

> 目标：把家里的**萤石摄像头**变成 my-agent 能用的一路视频源（和 USB 摄像头**并存**）。
> 本文是**可复制的端到端流程**：注册账号 → 建应用 → 接设备 → 生成播放地址 → 拉流 → 并入 my-agent。
> 适用于萤石（EZVIZ）云台机，如 **CS-C6TC-32WFR / CS-C6P-7A3WFR**。
> 文档版本: v1.0 · 2026-10-13

---

## 0. 一句话原理

萤石消费机**默认不开 RTSP/ONVIF**，但云账号能看到画面。取流的正路是：

```
萤石云账号 ──① ─▶ 萤石开放平台「应用」 ──② ─▶ 设备「接入」到应用 ──③ ─▶ 生成播放地址 ──④ ─▶ ffmpeg 拉流
   (App 登录)        (appKey/appSecret)         (序列号+验证码)          (RTMP/FLV/HLS)      (抽帧/送识别)
```

四道关卡缺一不可：
1. **云账号**：设备归属它（App 能看画面）。
2. **开放平台应用**：拿 `appKey/appSecret`。
3. **设备接入**：把设备「萤石协议接入」到应用（**要设备验证码**）——不接入则取流报 `60060`。
4. **播放地址**：在控制台「直播地址」生成（**带 `expire` 时效**，过期要重生成）。

> 关键坑：取流 API `/api/lapp/live/address/get` 对**自有设备**常返回 `60060 The address is unbound`，
> 真正能用的是**控制台设备详情 →「直播地址」**页生成的地址（走另一套后端）。
> 所以"生成地址"这一步要么**人工在控制台点**，要么**用 Chrome 自动化点**（见 §5）。

---

## 1. 前提

- 手机装 **萤石云视频 App**，用云账号登录、且已添加了这台摄像头（能看实时画面）。
- 本机能联网、有 `ffmpeg`、有 `google-chrome`。
- 账号里有两类凭据，**统一放 `~/.env`**（不要写进本文）：

| env key | 含义 |
|---------|------|
| `EZVIZ_ACCOUNT` / `EZVIZ_PASSWORD` | 萤石云账号（App 登录用，手机号+密码） |
| `EZVIZ_APPKEY` / `EZVIZ_APPSECRET` | 开放平台应用密钥 |
| `EZVIZ_CODE_<序列号>` | 该设备的「验证码」 |

---

## 2. Step ① 注册萤石云账号 + 添加设备

1. 手机应用商店装 **「萤石云视频」**（或海康「萤石」）。
2. 手机号注册/登录（本文示例账号 `EZVIZ_ACCOUNT`）。
3. App 首页 **「+」→ 添加设备 → 扫描机身二维码/选型号**，按向导把摄像头连上家里 WiFi。
   - 添加成功后 App 里能看到实时画面，这就是"设备属于该账号"。

> 已有设备的话跳过本步（只需确认 App 能看画面）。

---

## 3. Step ② 注册萤石开放平台 + 创建应用

1. 浏览器打开 **https://open.ys7.com/** ，用**同一个萤石云账号**登录 → 进控制台 `open.ys7.com/console/home.html`。
2. **账号中心 → 实名认证**（取流等能力通常要求认证）。
3. 进入 **「我的应用 / 应用管理」→ 创建应用**：
   - 应用名称随意；类型选「**自有应用 / 企业应用**」。
   - 创建后拿到 **AppKey** 和 **AppSecret**（各 32 位 hex），填入 `~/.env` 的 `EZVIZ_APPKEY` / `EZVIZ_APPSECRET`。
   - 若应用需要「视频直播」能力：在应用的**服务/能力**里开通（见 §9 排错）。

**用 AppKey/AppSecret 换 accessToken（验证密钥是否配对）：**

```bash
curl -s -X POST https://open.ys7.com/api/lapp/token/get \
  -d "appKey=$EZVIZ_APPKEY" -d "appSecret=$EZVIZ_APPSECRET"
# 成功: {"code":"200","data":{"accessToken":"at.xxxx","expireTime":...}}
# 失败: code 10030 = appKey/secret 不匹配；10017 = AppKey 不存在（可能建在国际站）
```

> 注意：`accessToken` 形如 `at.xxxx-xxxx-...`，**它本身不是 AppSecret**，别把两者搞混。

---

## 4. Step ③ 设备接入（要「设备验证码」）

### 4.1 设备验证码在哪

**每台设备独有的 6 位密钥**（大写字母/数字），两个来源：

1. **机身标签**（最稳）：断电取下摄像头，看**底座/背面标签**——
   ```
   型号: CS-C6TC-32WFR
   电源: 5V ⎓ ≤7W
   验证码: IXQNDK        ← 就是这个（6 位）
   序列号: 802657358     ← 设备序列号
   ```
   （标签还有二维码，扫它可快速添加。）
2. **萤石云 App**：选中设备 → 右上 **⚙ 设置 → 设备信息 / 关于** → 有一行 **「验证码」**。

> 序列号 = 设备序列号（deviceSerial），验证码 = validateCode（也叫加密密钥/encryptkey）。

### 4.2 接入操作（控制台）

1. 控制台 **设备管理器 → 设备管理 → 点「萤石协议接入」**。
2. 弹框填：**设备序列号** + **设备验证码** → 确定。
3. 设备出现在「设备管理」列表，**接入方式=萤石协议、状态=在线** 即成功。

> 若提示「设备已经被自己添加」= 已接入，无需再弄。

---

## 5. Step ④ 生成播放地址（控制台，可 Chrome 自动化）

### 5.1 手动（3 下点完）

**设备管理 → 找到设备 → 操作列「视频直播」→ 右侧「直播地址」标签页 → 点「重新生成」**，
页面给出 5 种地址：

| 格式 | 示例（前缀） | 用途 |
|------|--------------|------|
| **EZOPEN** | `ezopen://open.ys7.com/802657358/1.hd.live` | 萤石 SDK/网页播放器 |
| **RTMP** | `rtmp://rtmp01open.ys7.com:1935/v3/openlive/802657358_1_1?expire=...&t=...` | 标准 RTMP |
| **HTTP-FLV** | `https://rtmp09open.ys7.com:9188/v3/openlive/802657358_1_1.flv?expire=...` | 低延迟网页 |
| **HLS** | `https://open.ys7.com/v3/openlive/802657358_1_1.m3u8?expire=...` | **通用，最稳** |
| **LL-HLS** | `https://open.ys7.com/v3/openlive/llhls/...m3u8?expire=...` | 低延迟 HLS |

- URL 参数 `expire` = 过期时间戳（unix 秒），`t` = 签名。**地址是动态签名**，过期即失效。
- 若设备**开了视频加密**（`support_encrypt=1`），标准流一般已在服务端解密；个别场景需在 EZOPEN 地址里带验证码：`ezopen://<验证码>@open.ys7.com/<序列号>/1.rec`。

### 5.2 用 Chrome 自动化点（推荐，免人工找按钮）

遵循项目规则：**先用专用 Chrome（固定端口、带登录态）**，再走 CDP/MCP 操作。

```bash
# 1) 起专用 Chrome（同步登录态、固定端口 9222、免授权弹窗）
operator/tools/chrome_debug.sh
```

然后二选一操作页面：

**方式 A：chrome-devtools MCP（大脑直接调，推荐）**
```text
chrome-devtools_navigate_page  -> https://open.ys7.com/console/home.html
chrome-devtools_take_snapshot  -> 拿设备管理/应用的元素
chrome-devtools_click          -> 「设备管理 → 视频直播」→「直播地址」→「重新生成」
chrome-devtools_evaluate_script-> 读 document.body.innerText 里的 rtmp/hls 地址
```

**方式 B：agentkit `ak.cdp`（Lua 脚本化，按名操作）**
```lua
package.path = "/opt/my-agent/?.lua;/opt/my-agent/?/init.lua;" .. package.path
local ak = require("agentkit")
local cdp = ak.cdp            -- 经常驻守护 agentkit/tools/cdpd.js（连 Chrome 一次）
cdp.goto("https://open.ys7.com/console/device.html")
-- 用 DOM/文本定位并点击（示例：点某行的「视频直播」）
cdp.eval([[
  (()=>{let r=[...document.querySelectorAll('table tr')].find(x=>x.innerText.includes('802657358'));
   let a=r&&[...r.querySelectorAll('a,button')].find(b=>b.innerText.trim()==='视频直播');
   a&&a.click(); return r?'ok':'nf';})()
]])
-- 读「直播地址」页文本，正则抽出地址
print(cdp.text("body"))
```

> 断开点：点「重新生成」后页面会短暂请求后端生成地址（后端走的是萤石云直播内部接口，
> 与开放平台 `/api/lapp/live/address/get` 不是同一条）。**直接用页面渲染出来的文本最省事。**

---

## 6. Step ⑤ 拉流 & 抽帧

```bash
# 直接拉 HLS 抓一帧
ffmpeg -y -i "https://open.ys7.com/v3/openlive/802657358_1_1.m3u8?expire=...&t=..." \
  -frames:v 1 /tmp/ezviz.jpg

# 低延迟可换 FLV / RTMP（把上面 URL 换成对应格式即可）
```

> RTMP 若报 `Input/output error`：多半拿成了**推流地址**（域名 `*push*`），播放地址域名应是 `rtmp0xopen` / `hls0xopen`。

---

## 7. 地址时效与自动刷新

- 播放地址**会过期**（`expire` 到的时刻失效）。
- 自动刷新思路（二选一）：
  1. **控制台脚本化**：用 §5.2 的 Chrome 自动化，定时点「重新生成」→ 抓新地址 → 写文件。
  2. **本地 RTSP 中转缓存**（推荐，配合 §8）：一个常驻进程定期重新生成地址并重启 `ffmpeg`，
     对外暴露**固定的本地地址**，下游（my-agent）永远连本地这个，不感知过期。

---

## 8. 并入 my-agent（USB + 萤石 并存）——已实现

**现状**：`gui/flutter/` 的 agent 界面已支持**双路分屏**（左 USB、右萤石）。

**已落地的改动**
| 文件 | 改动 |
|------|------|
| `gui/flutter/linux/runner/camera_texture.cc` | 支持**双纹理源**：路1 `agent/camera`（USB 或 `RTSP_URL`）；路2 `agent/camera2`（URL 流，默认读 `/tmp/myagent_ezviz.url`，**每次重连重读**，可跟随刷新）。新增方法 `streamTextureId` / `snapshot2`。 |
| `gui/flutter/lib/app.dart` | 取第二路纹理 `streamTextureId`；有两路时 `Row` 分屏显示（`Center+AspectRatio(16:9)+Texture`）。 |
| `operator/tools/ezviz.lua` | 刷新地址：纯 API 换 token → 取 HLS 地址 → 写 `/tmp/myagent_ezviz.url`；`camera.sh --ezviz` 过期时自动调用。 |
| `agentkit/tools/ezviz_refresh.js` | 上面的 node 助手（CDP 单次操作）。 |

**启用各路流的开关**（原生侧）：
- `CAM2_URL` / `CAM3_URL`：直接给固定流地址（分别对应第 2、3 路）；
- 或 `CAM2_URL_FILE`（默认 `/tmp/myagent_ezviz.url`，客厅）、`CAM3_URL_FILE`（默认 `/tmp/myagent_door.url`，门口）——**文件存在即启用该路**（配合刷新脚本）；
- `CAM2_SNAPSHOT`/`CAM3_SNAPSHOT`：各路抓帧保存路径。原生按「1 USB + N 路流」动态建纹理，Dart 按数量 `Row` 分格。

**日常使用**
```bash
operator/tools/chrome_debug.sh                     # 起带登录态的专用 Chrome（首次/登录过期时）
operator/tools/camera.sh --ezviz keting --out /tmp/keting.jpg   # 客厅（地址过期自动刷新）
operator/tools/camera.sh --ezviz menkou --out /tmp/door.jpg    # 门口（设备需在线）
# 重启 app：桌面「agent」图标，或 bash gui/flutter/launch.sh
# 左 USB + 客厅 + 门口 分格；某路过期时重跑对应 camera.sh --ezviz（流重连即自动换新地址）
```

> **踩坑（已解决）**：Flutter Linux 里第二路纹理用 `FittedBox+SizedBox(1280×720)+clipBehavior` 会导致
> **纹理平铺/重影**；改用 `Center+AspectRatio(16:9)+Texture` 后正常。单纹理时不触发。

**方案 B（改代码）：让工具支持任意流 URL**
- 把 `operator/tools/camera.sh` 的 `--rtsp` 泛化为 `--url`（非 RTSP 时**不加** `-rtsp_transport tcp`）。
- `voice/camera`、`voice/app` 同理支持 HLS/RTMP URL。
- 改动要按项目规范：`plugin.sh` 元数据 → `index` → 重启大脑。

**按项目规范落地时**（不新增 Python）：
- 建议新增 **`agentkit/adapters/ezviz.lua`**：封装「登录取地址（Chrome/CDP）+ 本地转 RTSP + 刷新」；
- 建议新增 **`operator/tools/live.sh`**：`start | stop | status | url | shot`（取流/抽帧/并入识别）。

---

## 9. 排错速查

| 现象 | 原因 / 处理 |
|------|-------------|
| token `10030` | appKey/appSecret 不匹配（抄错/要重置 Secret） |
| token `10017` | AppKey 不存在（可能建在了国际站 `open.ezvilife.com`） |
| 取流 API 返回 `60060 The address is unbound` | 设备未「接入」，或**该 API 不适用自有设备** → 走控制台「直播地址」 |
| 接入报「validateCode 为空/错误」 | 验证码错 → 用标签/App 里的 6 位 |
| 播放地址报 I/O error | 拿成**推流地址**（`*push*` 域名）；要用 `rtmp0xopen`/`hls0xopen` |
| 浏览器连不上/反复弹授权 | 先 `tools/chrome_debug.sh`（专用固定端口实例） |
| 云账号登录触发「终端绑定」 | 萤石登录保护；改走 App 拿验证码人工接入最稳 |

---

## 10. 本机实测记录（示例）

| 项 | 值 |
|----|----|
| 云账号 | 见 `~/.env` `EZVIZ_ACCOUNT` |
| 开放平台应用 | 见 `~/.env` `EZVIZ_APPKEY` / `EZVIZ_APPSECRET` |
| 客厅摄像头 | **CS-C6TC-32WFR**，序列号 `802657358`，接入方式=萤石协议 |
| 门口摄像头 | **CS-C6P-7A3WFR**，序列号 `815311181` |
| 验证码位置 | 机身标签「验证码」行（如 `IXQNDK`）/ App 设备信息 |
| 播放地址 | 控制台设备详情→「直播地址」→ 重新生成（HLS 实测可拉） |

> 密钥一律存 `~/.env`；**不要**把 AppSecret / 验证码写进被 git 跟踪的文档。

---

## 11. 相关文档

- `chrome.md` — 专用 Chrome + CDP/MCP 的完整用法（控制台自动化看这份）。
- `operator/CAPABILITIES.md` §一 — 浏览器/CDP 能力清单。
- `operator/TOOLS.md` — `camera.sh`（USB/RTSP/HLS 抓帧）；登录态抓取走 CDP/对应工具。
- `operator/AGENTS.md` — 运行时契约（回程、白名单）。

---

*文档版本: v1.0 · 更新日期: 2026-10-13*
