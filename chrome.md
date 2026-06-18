# Chrome DevTools MCP 集成

> Chrome 官方发布的 MCP 服务器，让 AI 编码代理可以直接调试网页。

## 简介

[Chrome DevTools MCP](https://developer.chrome.com/blog/chrome-devtools-mcp?hl=zh-cn) 是 Chrome 官方发布的 MCP 服务器，将 Chrome 开发者工具的能力引入 AI 编码助理。AI 代理可以直接在 Chrome 中调试网页，检查 DOM/CSS、分析性能、模拟用户操作等。

## 安装

```bash
npx chrome-devtools-mcp@latest
```

## 配置

在 `~/.config/opencode/opencode.json` 的 `mcp` 字段中添加：

```json
"chrome-devtools": {
  "type": "local",
  "command": "npx",
  "args": ["chrome-devtools-mcp@latest"],
  "enabled": true
}
```

## 可用工具

| 分类 | 工具 | 用途 |
|------|------|------|
| **导航** | `new_page` / `navigate_page` | 打开/导航到 URL |
| | `close_page` / `list_pages` / `select_page` | 管理标签页 |
| | `wait_for` | 等待页面元素出现 |
| **截图** | `take_screenshot` | 页面/元素截图 |
| **结构** | `take_snapshot` | 获取无障碍树（含元素 uid） |
| **操作** | `click` / `click_at` | 点击元素/坐标 |
| | `fill` / `fill_form` | 填表单 |
| | `hover` | 悬停 |
| | `type_text` / `press_key` | 键盘输入 |
| | `drag` | 拖拽 |
| | `upload_file` | 上传文件 |
| **脚本** | `evaluate_script` | 在页面中执行 JS |
| **调试** | `list_console_messages` / `get_console_message` | 查看控制台 |
| | `list_network_requests` / `get_network_request` | 分析网络请求 |
| **性能** | `performance_start_trace` / `performance_stop_trace` | 性能分析 |
| | `performance_analyze_insight` | 分析性能洞察 |
| | `lighthouse_audit` | Lighthouse 审计 |
| **模拟** | `emulate` | 模拟设备/网络/地理位置 |
| | `resize_page` | 调整视口 |
| **对话框** | `handle_dialog` | 处理浏览器对话框 |

## 示例提示

```
Verify in the browser that your change works as expected.
Why does submitting the form fail after entering an email address?
The page on localhost:8080 looks strange. Check what's happening.
Localhost:8080 is loading slowly. Make it load faster.
A few images on localhost:8080 are not loading. What's happening?
```

## 注意事项

- 使用时请确保 Chrome 已登录（未登录的浏览器无法操作需要登录的网站）
- MCP 服务器需要保持运行，opencode 会自动管理
- 首次启动会提示收集使用统计，可通过 `--no-usage-statistics` 关闭

---

*文档版本: 1.0*
*更新日期: 2026-06-18*
