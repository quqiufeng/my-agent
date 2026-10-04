# operator — 远程操作大脑（单脑 + 工具白名单）

把「手机微信 / 语音」变成对这台电脑的远程遥控。核心是**一个常驻 opencode**（单脑）：
语音和微信文本都转发给它，它按 `AGENTS.md` 的规则，**只能**调用 `tools/` 里白名单脚本。

```
语音 ─STT─▶ ┐
            ├─▶ opencode(4097) ──▶ 只允许调用 tools/*.sh ──▶ 操作本机
微信 ─OCR─▶ ┘        （AGENTS.md 契约 + opencode.json 权限 + guard 插件）
```

## 目录

```
operator/
├── AGENTS.md                     # 操作契约（模型读：来源识别/回程/白名单/禁止项）
├── opencode.json                 # 权限：默认全拒，只放行 tools/*
├── .opencode/plugin/guard.js     # 兜底：拦截 `tools/x.sh && rm -rf` 这类拼接
├── start.sh                      # 启动 tmux + opencode serve/attach
├── tools/                        # 白名单工具（唯一可执行入口）
│   ├── say.sh                    # 语音回程（USB 音响）
│   ├── wechat_send.sh            # 发微信文本（默认文件传输助手，可 --to 指定）
│   ├── wechat_send_file.sh       # 发文件/图片
│   ├── screenshot.sh             # 截屏，返回路径
│   ├── open_app.sh               # 打开白名单应用
│   ├── browser.sh                # 操作 Chrome
│   └── remote.sh                 # 管理 tmux/opencode 集群
└── README.md
```

## 启动

```bash
operator/start.sh            # 前台：启动 serve + attach TUI
operator/start.sh --bg       # 后台
```

## 白名单（只允许这些，其余一律拒绝）

| 工具 | 说明 |
|------|------|
| `say.sh "文本"` | USB 音响朗读 |
| `wechat_send.sh "文本"` / `--to 联系人 "文本"` | 发微信（默认文件传输助手） |
| `wechat_send_file.sh <路径> [--to 联系人]` | 发文件/图片 |
| `screenshot.sh [路径]` | 截屏 |
| `open_app.sh <chrome\|terminal\|files\|editor\|wechat>` | 开应用 |
| `browser.sh new_tab\|open\|search\|ai_search\|screenshot` | 浏览器 |
| `remote.sh status\|start\|stop ...` | 集群/会话 |

## 三层防护

1. **权限**：`opencode.json` 里 `bash` 默认 `deny`、只放行 `tools/*`；`read/edit/webfetch` 等一律 `deny`。
2. **兜底插件**：`guard.js` 在执行前再校验，禁止 `&&`、`;`、`|`、重定向等拼接绕过。
3. **契约**：`AGENTS.md` 告诉模型“只能这七件事，不认识的请求就拒绝”。

## 注意

- 改完 `opencode.json` / `guard.js` / `AGENTS.md` 后需**重启 opencode** 才生效。
- `AGENTS.md` 必须随 opencode 的**工作目录**（本目录）一起启动，故 `start.sh` 里 `cd operator/`。
  仓库根目录另有一份 `AGENTS.md`（仓库级开发指南）是给人看的，注意别放错目录。
- 模型后端在 `opencode.json` 的 `model` / provider 里配置（当前未写死，用你的默认）。
