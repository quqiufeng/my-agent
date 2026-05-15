# 微信 Bot API 技术解析：iLink 协议接入指南

> **来源**：[hao-ji-xing/openclaw-weixin](https://github.com/hao-ji-xing/openclaw-weixin)  
> **协议版本**：@tencent-weixin/openclaw-weixin@1.0.2  
> **更新日期**：2026年3月

---

## 1. 背景与概述

### 1.1 历史性突破

2026年，腾讯通过 [OpenClaw](https://docs.openclaw.ai) 框架正式开放微信个人账号的 Bot API（官方名称：**微信 ClawBot 插件功能**），底层协议称为 **iLink（智联）**。

**接入域名**：`ilinkai.weixin.qq.com` —— 腾讯官方服务器。

腾讯为此发布了专项使用条款《微信ClawBot功能使用条款》，签订地为深圳市南山区。**这是官方产品，非灰色地带。**

### 1.2 与旧方案对比

| 维度 | 旧方案（WeChatPadPro/itchat） | iLink Bot API（官方） |
|------|------------------------------|---------------------|
| **合法性** | 违反微信服务协议，灰色地带 | **官方开放，合法合规** |
| **稳定性** | 微信更新即失效 | 服务器端 API，稳定可靠 |
| **封号风险** | 极高 | 正常使用无风险 |
| **协议层** | 模拟 iPad/移动端协议 | HTTP/JSON 标准接口 |
| **媒体支持** | 有限 | 图片/语音/文件/视频完整支持 |
| **群聊** | 需特殊处理 | 原生支持（`group_id`） |

---

## 2. 官方 npm 包

### 2.1 包清单

| 包名 | 类型 | 说明 |
|------|------|------|
| `@tencent-weixin/openclaw-weixin-cli` | CLI 工具 | 安装引导、扫码登录 |
| `@tencent-weixin/openclaw-weixin` | 协议 SDK | 完整 iLink 协议实现（41 个 TS 文件） |

### 2.2 SDK 源码结构

```
src/
├── auth/          # QR 码登录、账号存储
├── api/           # iLink HTTP API 封装
├── cdn/           # 媒体文件 AES-128-ECB 加解密 + CDN 上传
├── messaging/     # 消息收发、inbound/outbound 处理
├── monitor/       # 长轮询主循环
├── config/        # 配置 schema
└── storage/       # 状态持久化
```

### 2.3 CLI 安装命令

```bash
npx @tencent-weixin/openclaw-weixin-cli install
```

CLI 工具职责：
1. 检测本机是否安装 `openclaw` CLI
2. 调用 `openclaw plugins install "@tencent-weixin/openclaw-weixin"` 安装插件
3. 触发 `openclaw channels login` 引导扫码
4. 重启 OpenClaw Gateway

---

## 3. iLink Bot API 协议详解

### 3.1 基础信息

- **协议**：HTTP/JSON
- **域名**：`https://ilinkai.weixin.qq.com`
- **CDN 域名**：`https://novac2c.cdn.weixin.qq.com/c2c`
- **鉴权方式**：Bearer Token（`bot_token`）
- **无需 SDK**，可直接 `fetch/curl` 调用

### 3.2 请求头规范

所有请求必须携带以下 Header：

```json
{
  "Content-Type": "application/json",
  "AuthorizationType": "ilink_bot_token",
  "X-WECHAT-UIN": "<base64(random_uint32)>"
}
```

**登录后额外携带**：

```json
{
  "Authorization": "Bearer <bot_token>"
}
```

> **注意**：`X-WECHAT-UIN` 每次请求随机生成一个 uint32，转十进制字符串后 base64 编码，用于防重放攻击。

### 3.3 完整 API 列表

| Endpoint | Method | 功能说明 |
|----------|--------|----------|
| `/ilink/bot/get_bot_qrcode` | GET | 获取登录二维码（需 `?bot_type=3`） |
| `/ilink/bot/get_qrcode_status` | GET | 轮询扫码状态（需 `?qrcode=xxx`） |
| `/ilink/bot/getupdates` | POST | **长轮询收消息（核心接口）** |
| `/ilink/bot/sendmessage` | POST | 发送消息（文字/图片/文件/视频/语音） |
| `/ilink/bot/getuploadurl` | POST | 获取 CDN 预签名上传地址 |
| `/ilink/bot/getconfig` | POST | 获取 typing_ticket |
| `/ilink/bot/sendtyping` | POST | 发送"正在输入"状态 |

---

## 4. 鉴权流程

### 4.1 流程图

```
开发者               iLink 服务器               微信用户
   │                      │                        │
   │── GET get_bot_qrcode ──▶│                        │
   │◀──── { qrcode, url } ──│                        │
   │                      │◀─── 用户扫码 ────────────│
   │── GET get_qrcode_status ──▶│（长轮询）              │
   │◀── { status: "confirmed",  │                        │
   │      bot_token, baseurl } ──│                        │
   │                      │                        │
   │  持久化 bot_token，后续所有请求 Bearer 鉴权         │
```

### 4.2 接口详情

#### 4.2.1 获取二维码

```http
GET https://ilinkai.weixin.qq.com/ilink/bot/get_bot_qrcode?bot_type=3
```

**响应**：

```json
{
  "qrcode": "xxx",
  "qrcode_img_content": "<base64图片数据>"
}
```

#### 4.2.2 轮询扫码状态

```http
GET https://ilinkai.weixin.qq.com/ilink/bot/get_qrcode_status?qrcode=<qrcode>
```

**响应**：

```json
{
  "status": "confirmed",
  "bot_token": "<token>",
  "baseurl": "<base_url>"
}
```

**状态值**：
- `pending` — 等待扫码
- `scanned` — 已扫码，等待确认
- `confirmed` — 已确认，返回 `bot_token`
- `expired` — 二维码过期

---

## 5. 消息收取：长轮询机制

### 5.1 机制说明

与 Telegram Bot API 的 `getUpdates` 设计完全一致：

- 服务器 **hold 连接最多 35 秒**
- 有新消息时立即返回
- 无消息时超时返回，客户端需重新请求

### 5.2 请求示例

```http
POST /ilink/bot/getupdates
Content-Type: application/json
Authorization: Bearer <bot_token>

{
  "get_updates_buf": "<上次返回的游标，首次为空字符串>",
  "base_info": { "channel_version": "1.0.2" }
}
```

### 5.3 响应示例

```json
{
  "ret": 0,
  "msgs": [
    { ...WeixinMessage... }
  ],
  "get_updates_buf": "<新游标，下次请求必须带上>",
  "longpolling_timeout_ms": 35000
}
```

> **关键**：`get_updates_buf` 是游标机制，类似数据库 cursor，**必须每次更新**，否则会重复收到消息。

---

## 6. 消息结构

### 6.1 消息对象（WeixinMessage）

```json
{
  "from_user_id": "o9cq800kum_xxx@im.wechat",
  "to_user_id": "e06c1ceea05e@im.bot",
  "message_type": 1,
  "message_state": 2,
  "context_token": "AARzJWAFAAABAAAAAAAp...",
  "item_list": [
    {
      "type": 1,
      "text_item": { "text": "你好" }
    }
  ]
}
```

### 6.2 ID 格式规律

| 类型 | 格式 | 示例 |
|------|------|------|
| 用户 ID | `xxx@im.wechat` | `o9cq800kum_xxx@im.wechat` |
| Bot ID | `xxx@im.bot` | `e06c1ceea05e@im.bot` |

### 6.3 消息类型（item_list[].type）

| type | 含义 | 说明 |
|------|------|------|
| 1 | **文本** | `text_item.text` |
| 2 | **图片** | CDN 加密存储 |
| 3 | **语音** | silk 编码，附带转文字 |
| 4 | **文件附件** | CDN 加密存储 |
| 5 | **视频** | CDN 加密存储 |

### 6.4 message_type 字段含义

| 值 | 含义 |
|----|------|
| 1 | 用户发送的消息（inbound） |
| 2 | Bot 发送的消息（outbound） |

### 6.5 message_state 字段含义

| 值 | 含义 |
|----|------|
| 2 | `FINISH`（完整消息） |

---

## 7. context_token：对话关联核心

### 7.1 重要性

**这是整个协议中最关键、最容易踩坑的细节。**

每条收到的消息都带有 `context_token`，回复时必须**原样带上**，否则消息不会关联到正确的对话窗口。

### 7.2 使用示例

```json
POST /ilink/bot/sendmessage
Authorization: Bearer <bot_token>

{
  "msg": {
    "to_user_id": "o9cq800kum_xxx@im.wechat",
    "message_type": 2,
    "message_state": 2,
    "context_token": "<从 inbound 消息里取，必填！>",
    "item_list": [
      { "type": 1, "text_item": { "text": "你好！" } }
    ]
  }
}
```

---

## 8. 发送消息

### 8.1 接口

```http
POST /ilink/bot/sendmessage
Authorization: Bearer <bot_token>
```

### 8.2 文本消息

```json
{
  "msg": {
    "to_user_id": "<用户ID>",
    "message_type": 2,
    "message_state": 2,
    "context_token": "<从收到的消息获取>",
    "item_list": [
      { "type": 1, "text_item": { "text": "回复内容" } }
    ]
  }
}
```

### 8.3 媒体消息

发送图片/文件/语音/视频需要额外的 CDN 流程（见第9章）。

---

## 9. 媒体文件处理

### 9.1 加密机制

微信 CDN 上的所有媒体文件都经过 **AES-128-ECB** 加密：

```javascript
// 上传前加密
const encrypted = encryptAesEcb(fileBuffer, aesKey);

// CDN 下载后解密
const plaintext = decryptAesEcb(encryptedBuffer, aesKey);
```

### 9.2 发送图片完整流程

1. 生成随机 AES-128 key
2. 用 AES-128-ECB 加密文件
3. 调用 `getuploadurl` 获取预签名 URL
4. PUT 加密文件到 CDN
5. 在 `sendmessage` 中带上 `aes_key`（base64）和 CDN 引用参数

### 9.3 获取上传地址

```http
POST /ilink/bot/getuploadurl
Authorization: Bearer <bot_token>

{
  "file_name": "image.png",
  "file_size": 12345,
  "file_type": "image"
}
```

**响应**：

```json
{
  "upload_url": "https://novac2c.cdn.weixin.qq.com/c2c/...",
  "aes_key": "<base64编码的AES密钥>"
}
```

---

## 10. 正在输入状态

### 10.1 获取 typing_ticket

```http
POST /ilink/bot/getconfig
Authorization: Bearer <bot_token>
```

### 10.2 发送 typing 状态

```http
POST /ilink/bot/sendtyping
Authorization: Bearer <bot_token>

{
  "to_user_id": "<用户ID>",
  "typing_ticket": "<从getconfig获取>",
  "context_token": "<从收到的消息获取>"
}
```

---

## 11. 最简裸调 Demo（Node.js）

不依赖 `openclaw` 的纯 HTTP 实现：

```javascript
const BASE_URL = "https://ilinkai.weixin.qq.com";

// ========== 工具函数 ==========
async function apiPost(endpoint, body, token) {
  const headers = {
    "Content-Type": "application/json",
    "AuthorizationType": "ilink_bot_token",
    "X-WECHAT-UIN": Buffer.from(String(Math.floor(Math.random() * 4294967295))).toString("base64"),
  };
  if (token) headers["Authorization"] = `Bearer ${token}`;

  const res = await fetch(`${BASE_URL}/${endpoint}`, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
  return res.json();
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

// ========== 1. 获取二维码 ==========
async function getQRCode() {
  const res = await fetch(`${BASE_URL}/ilink/bot/get_bot_qrcode?bot_type=3`);
  return res.json(); // { qrcode, qrcode_img_content }
}

// ========== 2. 等待扫码 ==========
async function waitForScan(qrcode) {
  while (true) {
    const res = await fetch(`${BASE_URL}/ilink/bot/get_qrcode_status?qrcode=${qrcode}`);
    const status = await res.json();

    if (status.status === "confirmed") {
      return { botToken: status.bot_token, baseUrl: status.baseurl };
    }
    await sleep(1000);
  }
}

// ========== 3. 长轮询收消息 + 回复 ==========
async function main() {
  // 获取二维码并展示给用户
  const { qrcode, qrcode_img_content } = await getQRCode();
  console.log("请扫码登录，qrcode:", qrcode);
  // TODO: 展示 qrcode_img_content（base64图片）给用户

  // 等待用户扫码确认
  const { botToken } = await waitForScan(qrcode);
  console.log("登录成功，bot_token:", botToken);

  // 长轮询收消息
  let getUpdatesBuf = "";
  while (true) {
    const { msgs, get_updates_buf } = await apiPost(
      "ilink/bot/getupdates",
      { get_updates_buf: getUpdatesBuf, base_info: { channel_version: "1.0.2" } },
      botToken
    );
    getUpdatesBuf = get_updates_buf ?? getUpdatesBuf;

    for (const msg of msgs ?? []) {
      if (msg.message_type !== 1) continue; // 只处理用户消息
      const text = msg.item_list?.[0]?.text_item?.text;
      console.log(`收到消息: ${text}`);

      // 回复消息（必须带 context_token）
      await apiPost("ilink/bot/sendmessage", {
        msg: {
          to_user_id: msg.from_user_id,
          message_type: 2,
          message_state: 2,
          context_token: msg.context_token,
          item_list: [{ type: 1, text_item: { text: `回复：${text}` } }]
        }
      }, botToken);
    }
  }
}

main().catch(console.error);
```

---

## 12. 接入 Claude Code Agent

配合 `@anthropic-ai/claude-agent-sdk`，15 分钟搭出 AI 助手：

```javascript
import { query } from "@anthropic-ai/claude-agent-sdk";

async function askClaude(userText) {
  async function* messages() {
    yield {
      type: "user",
      session_id: "",
      parent_tool_use_id: null,
      message: { role: "user", content: userText },
    };
  }

  let result = "";
  for await (const msg of query({
    prompt: messages(),
    options: {
      model: "sonnet",
      baseTools: [{ preset: "default" }],  // Bash, Read, WebSearch...
      deniedTools: ["AskUserQuestion"],
      cwd: process.cwd(),
      env: process.env,
      abortController: new AbortController(),
    },
  })) {
    if (msg.type === "result") result = msg.result ?? "";
  }
  return result;
}

// 收到微信消息后
const reply = await askClaude(inboundText);
await sendWeixinMessage(toUserId, reply, contextToken);
```

---

## 13. 官方条款与合规边界

### 13.1 腾讯定位：纯管道

> "我们仅提供微信ClawBot插件与第三方AI服务的信息收发，不存储你的输入内容与输出结果，不提供AI相关服务。"

- 腾讯不存储消息内容
- 腾讯不提供 AI 服务
- 你接入的 AI 服务由你自行负责

### 13.2 腾讯保留控制权

腾讯有权：
- 决定支持的客户端类型和使用条件
- 决定可连接的第三方 AI 服务类型和范围
- 对内容进行识别、过滤、拦截
- 根据安全情况采取阻断措施
- **随时变更、中断、中止或终止服务**

### 13.3 数据隐私

| 数据类型 | 处理方式 |
|----------|----------|
| 消息内容（文字/图片/语音/视频/文件） | **不存储**，仅转发 |
| AI 输出结果 | **不存储**，仅转发 |
| IP 地址、操作记录、设备信息 | **会被收集**，用于安全审计 |

### 13.4 明确禁止的行为

- 绕过、破解微信软件的技术保护措施
- 违反国家法律法规
- 危害网络安全、数据安全及微信产品安全
- 侵犯他人合法权益

### 13.5 风险提示

- **不应将核心业务完全依赖这套 API**，需要有降级方案
- 腾讯可能随时限速或封禁特定 AI 服务
- 服务可能随时终止

---

## 14. 技术限制与已知问题

| 限制项 | 说明 |
|--------|------|
| `bot_type=3` | 含义未完全明确，源码硬编码，可能对应特定账号类型或套餐 |
| OpenClaw 账号 | 登录流程需要连接 iLink 服务器，可能需要 OpenClaw 平台审核或注册 |
| 群聊支持 | 源码有 `group_id` 字段和 `ChatType: "direct"` 注释，群聊可能需要额外权限 |
| 消息历史 | 没有拉取历史消息的 API，只有 `get_updates_buf` 游标机制 |
| 速率限制 | 官方未公开，需实测 |

---

## 15. 合规应用场景

基于这套 API，可以合法构建：

- **个人 AI 助手** — 直接在微信里使用 Claude / GPT（已实测）
- **通知机器人** — 监控报警、部署状态推送到微信
- **客服系统** — 多账号管理 + 自动分流
- **工作流自动化** — 接收微信指令触发 CI/CD、文件处理等
- **家庭群助手** — 家庭群内的 AI 助手
- **个人知识库** — 发消息自动归档到 Notion/飞书

---

## 16. 资源链接

| 资源 | 链接 |
|------|------|
| Demo 仓库 | https://github.com/hao-ji-xing/openclaw-weixin |
| OpenClaw 文档 | https://docs.openclaw.ai |
| 插件包 npm | https://www.npmjs.com/package/@tencent-weixin/openclaw-weixin |
| CLI 包 npm | https://www.npmjs.com/package/@tencent-weixin/openclaw-weixin-cli |

---

## 17. 接入本项目（钉钉 Agent 系统）的规划建议

### 17.1 架构对比

| 维度 | 钉钉接入（现有） | 微信接入（新增） |
|------|-----------------|-----------------|
| 入口协议 | 钉钉 WebSocket Stream | iLink HTTP/JSON |
| 消息收取 | 钉钉主动推送 | 长轮询 getupdates |
| 鉴权方式 | 钉钉 AppKey/AppSecret | QR 码扫码 + bot_token |
| 消息格式 | 钉钉消息对象 | WeixinMessage |
| 媒体处理 | 钉钉 CDN | 微信 CDN + AES-128-ECB |
| 群聊支持 | 已支持 | 需验证 |

### 17.2 建议实现方案

1. **新增 weixin 模块**：`ding/weixin/` 或 `weixin/`
2. **核心组件**：
   - `weixin_gateway.py` — 封装 iLink API（登录、长轮询、发送消息）
   - `weixin_auth.py` — QR 码登录流程
   - `weixin_message.py` — 消息解析与构造
   - `weixin_media.py` — 媒体文件加解密与 CDN 上传
3. **复用现有架构**：
   - 消息接收后转换为统一格式
   - 复用 `task_worker.py` 的任务分发机制
   - 复用 `tasks/` 目录的插件系统
4. **关键注意点**：
   - 必须正确处理 `context_token`
   - 长轮询需要独立线程/进程
   - 媒体文件需要 AES-128-ECB 加解密
   - 需要持久化 `bot_token` 和 `get_updates_buf`

---

*本文基于对 `@tencent-weixin/openclaw-weixin@1.0.2` 源码的分析和实测整理，截止 2026年3月。*
