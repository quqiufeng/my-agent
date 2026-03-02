# 脚本版 OpenCode 设计

## 核心设计思路

**本质：定义一套标签原语 + 实现执行逻辑 + 远程 API 返回约定格式 = 本地自我更新**

```
远程大模型 API 返回 → 标签包裹内容 → 本地解析执行 → 结果反馈
        ↑                                                    │
        └──────────────── 失败重试 ←────────────────────────┘
```

关键点：
1. **标签原语**：我们定义一套操作标签（如 `#shell`、`#code`、`#file`）
2. **执行逻辑**：本地实现标签的解析和执行
3. **约定格式**：远程 API 只需返回标签包裹的内容，无需知道具体实现
4. **自我更新**：Python 自省能力 + 标签执行 = 脚本可以修改自己

---

## 标签原语定义

```markdown
#shell
执行 shell 命令
#end

#code 文件路径
写入代码文件
#end

#file 文件路径
读取文件内容
#end

#test
运行测试验证
#end
```

---

## 执行逻辑实现

| 标签 | 本地执行 |
|:---|:---|
| `#shell` | subprocess.run() 执行命令 |
| `#code` | 写入文件 + 语法检查 + .bak 备份 |
| `#file` | 读取文件内容返回 |
| `#test` | pytest / python -c 执行验证 |

---

## 交互流程

```
1. 用户输入需求
2. 本地扫描项目生成上下文
3. 发送给远程 API（包含标签定义）
4. API 返回标签包裹的内容：
   #shell
   pip install redis
   #end
   
   #code user.py
   class User:
       pass
   #end
5. 本地解析标签，执行对应操作
6. 验证结果，失败则反馈给 API 重试
7. 完成
```

---

## 为什么能自我更新

1. **Python 自省**：inspect 可以读取函数签名、源码、类型
2. **标签执行**：API 返回 `#code 脚本自身` 就能修改脚本
3. **闭环验证**：`python -c` 执行验证修改是否正确
4. **循环迭代**：失败 → 反馈 → 修复 → 重试

---

## 安全限制

| 项目 | 实现 |
|:---|:---|
| Shell 白名单 | python, pip, git, pytest |
| 超时 | 30 秒 |
| 备份 | .bak 文件 |
| 语法检查 | compile() 验证 |

---

## 完整模块设计

### 1. 核心设计理念

#### 1.1 和 OpenCode 的区别

| 特性 | OpenCode 完整版 | 简化版 |
|------|----------------|--------|
| 支持语言 | 多语言 (Go/JS/Rust...) | **仅 Python** |
| LLM API | 多模型切换 | **单一 API（配置 URL）** |
| 用户界面 | TUI 交互界面 | **无交互，CLI 参数调用** |
| 多 Agent | 6+ 主/子代理 | 1 个 Agent |
| 调试方式 | 复杂架构调试 | **改提示词** |

#### 1.2 核心不变的部分

```
┌─────────────────────────────────────────────────────────────┐
│                    OpenCode 核心架构                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   用户输入 → 消息历史 → LLM API → 工具执行 → 返回结果     │
│                      ↑                                      │
│                   滑动窗口                                   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                      简化版架构                              │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   CLI 参数 → 消息构造 → 单一 API → 工具执行 → 输出结果    │
│                                                             │
│   区别：去掉人机交互，LLM 返回什么就执行什么              │
│         执行结果放回上下文，继续调用直到完成                │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

### 2. 整体架构

#### 2.1 简化版架构

```
┌─────────────────────────────────────────────────────────────────┐
│                      简化版架构                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   ┌──────────────────────────────────────────────────────────┐  │
│   │                      CLI 入口                              │  │
│   │              python main.py --task "任务"                  │  │
│   └─────────────────────────┬────────────────────────────────┘  │
│                             │                                    │
│                             ▼                                    │
│   ┌──────────────────────────────────────────────────────────┐  │
│   │                    消息构造器                              │  │
│   │  • 系统提示词                                              │  │
│   │  • 项目上下文                                              │  │
│   │  • 历史消息（滑动窗口）                                    │  │
│   └─────────────────────────┬────────────────────────────────┘  │
│                             │                                    │
│                             ▼                                    │
│   ┌──────────────────────────────────────────────────────────┐  │
│   │                    单一 API 调用                          │  │
│   │           (用户配置的 URL + API Key)                      │  │
│   └─────────────────────────┬────────────────────────────────┘  │
│                             │                                    │
│                             ▼                                    │
│   ┌──────────────────────────────────────────────────────────┐  │
│   │                    工具执行器                             │  │
│   │  • 解析 LLM 返回的动作                                    │  │
│   │  • 执行文件读写/代码执行                                   │  │
│   │  • 返回执行结果                                            │  │
│   └─────────────────────────┬────────────────────────────────┘  │
│                             │                                    │
│                             ▼                                    │
│   ┌──────────────────────────────────────────────────────────┐  │
│   │                    循环调用                               │  │
│   │  (执行结果 → 加入上下文 → 继续调用 → 直到完成)           │  │
│   └──────────────────────────────────────────────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

### 3. 模块拆分

#### 3.1 目录结构

```
python-ai/
├── main.py              # CLI 入口
├── api.py               # API 调用
├── prompt.py            # 提示词管理
├── tool.py              # 工具集（文件/执行）
├── context.py           # 上下文管理
├── config.json          # 配置文件
└── requirements.txt     # 依赖
```

#### 3.2 模块说明

| 模块 | 职责 | 代码量 |
|------|------|--------|
| **main.py** | CLI 入口，参数解析，循环控制 | ~30 行 |
| **api.py** | HTTP 请求封装 | ~30 行 |
| **prompt.py** | 提示词构造 | ~50 行 |
| **tool.py** | 工具解析与执行 | ~80 行 |
| **context.py** | 消息历史管理 | ~50 行 |
| **config.json** | API 配置 | ~10 行 |
| **总计** | | **~250 行** |

---

### 4. 上下文管理

#### 4.1 和 OpenCode 一样的设计

```
┌─────────────────────────────────────────────────────────────┐
│                    上下文层级                                │
├─────────────────────────────────────────────────────────────┤
│  Level 4: 项目摘要                                           │
│         项目结构、依赖关系、README                           │
├─────────────────────────────────────────────────────────────┤
│  Level 3: 文件快照                                          │
│         当前操作的文件内容                                    │
├─────────────────────────────────────────────────────────────┤
│  Level 2: 模型输出                                          │
│         AI 生成的代码、建议                                   │
├─────────────────────────────────────────────────────────────┤
│  Level 1: 用户输入                                          │
│         CLI 参数传入的任务描述                                │
└─────────────────────────────────────────────────────────────┘
```

#### 4.2 滑动窗口

```python
# context.py
class Context:
    def __init__(self, max_history=20):
        self.messages = []
        self.max_history = max_history
    
    def add(self, role: str, content: str):
        self.messages.append({"role": role, "content": content})
        # 滑动窗口：只保留最近 N 条
        if len(self.messages) > self.max_history:
            self.messages = self.messages[-self.max_history:]
    
    def build(self, system_prompt: str, project_info: str) -> list:
        msgs = [{"role": "system", "content": system_prompt}]
        msgs.append({"role": "system", "content": f"项目信息:\n{project_info}"})
        msgs.extend(self.messages)
        return msgs
```

---

### 5. 核心流程

#### 5.1 工作流程

```
1. 用户执行: python main.py --task "写个登录接口"
                    │
                    ▼
2. 扫描项目结构 → 生成项目摘要
                    │
                    ▼
3. 构建初始消息 → [系统提示] + [项目摘要] + [用户任务]
                    │
                    ▼
4. 调用 LLM API → 获取响应
                    │
                    ▼
5. 解析响应 → 是否包含工具调用?
    │
    ├── 否 → 输出结果，结束
    │
    └── 是 → 执行工具 → 获取执行结果
                          │
                          ▼
              执行结果回到步骤 4加入上下文 → 
                          │
                    (最多循环 N 次)
```

#### 5.2 主循环代码

```python
# main.py
def main():
    args = parse_args()
    project_info = scan_project(args.project or ".")
    ctx = Context()
    
    for i in range(MAX_LOOPS):
        # 构建消息
        messages = ctx.build(get_system_prompt(), project_info)
        messages.append({"role": "user", "content": args.task})
        
        # 调用 API
        response = call_api(messages)
        
        # 执行工具
        result = execute_tool(response)
        
        # 检查是否完成
        if result.is_done:
            print(result.output)
            break
        
        # 把执行结果加入上下文，继续
        ctx.add("assistant", response)
        ctx.add("system", f"执行结果:\n{result.output}")
    else:
        print("未完成任务")
```

---

### 6. 提示词设计

#### 6.1 系统提示词

```python
# prompt.py
SYSTEM_PROMPT = """你是一个 Python 编程助手。

工作流程：
1. 理解用户需求
2. 分析项目现有结构
3. 生成或修改代码
4. 如果需要验证，运行代码检查

输出格式：
- 直接返回结果：直接输出代码或说明
- 执行工具：返回 JSON 格式动作

动作格式：
```
###ACTION###
{"type": "write", "file": "路径", "content": "代码"}
```
或
```
###ACTION###
{"type": "exec", "cmd": "命令"}
```
"""
```

#### 6.2 调试方式

```
LLM 返回不符合预期?
    │
    ▼
改 prompt.py 里的提示词
    │
    ▼
重新运行，直到 OK
```

---

### 7. 工具执行

#### 7.1 支持的工具

| 工具 | 说明 |
|------|------|
| **write** | 写文件 |
| **exec** | 执行命令 |
| **read** | 读文件 |

#### 7.2 工具解析

```python
# tool.py
import re
import json
import subprocess
import os

def execute_tool(response: str) -> ToolResult:
    # 解析 ###ACTION### 块
    match = re.search(r'###ACTION###\s*(\{.*?\})', response, re.DOTALL)
    if not match:
        return ToolResult(done=True, output=response)
    
    action = json.loads(match.group(1))
    
    if action["type"] == "write":
        path = action["file"]
        os.makedirs(os.path.dirname(path), exist_ok=True)
        open(path, "w", encoding="utf-8").write(action["content"])
        return ToolResult(done=True, output=f"已写入: {path}")
    
    if action["type"] == "exec":
        result = subprocess.run(
            action["cmd"], 
            shell=True, 
            capture_output=True, 
            text=True,
            cwd=action.get("cwd", ".")
        )
        output = result.stdout + result.stderr
        return ToolResult(done=False, output=output)
    
    return ToolResult(done=True, output="未知动作类型")
```

---

### 8. API 调用

#### 8.1 统一接口

```python
# api.py
import requests

def call_api(messages: list, config: dict) -> str:
    resp = requests.post(
        f"{config['url']}/chat/completions",
        headers={
            "Authorization": f"Bearer {config['key']}",
            "Content-Type": "application/json"
        },
        json={
            "model": config["model"],
            "messages": messages,
            "temperature": 0.7
        },
        timeout=60
    )
    resp.raise_for_status()
    return resp.json()["choices"][0]["message"]["content"]
```

#### 8.2 配置文件

```json
// config.json
{
    "url": "https://api.example.com/v1",
    "key": "sk-xxxxx",
    "model": "gpt-4",
    "max_loops": 5,
    "project": "."
}
```

---

### 9. 使用方式

#### 9.1 基本用法

```bash
# 写一个登录接口
python main.py --task "在 src/auth/ 下写一个登录接口"

# 添加单元测试
python main.py --task "为 src/auth/login.py 写单元测试"

# 运行测试
python main.py --task "运行 pytest"

# 修复 bug
python main.py --task "修复 src/auth/login.py 的登录 bug"
```

#### 9.2 指定项目目录

```bash
python main.py --project /path/to/project --task "任务描述"
```

---

### 10. 对比总结

| 项目 | OpenCode 完整版 | 简化版 |
|------|----------------|--------|
| 代码量 | 10万+ 行 | ~250 行 |
| 依赖 | 复杂 | requests |
| 界面 | TUI 交互 | 无 |
| 语言 | 多语言 | Python |
| API | 多模型 | 单一 |
| 调试 | 复杂 | 改提示词 |
| 多 Agent | 有 | 无 |

---

### 11. 完整代码清单

#### main.py (~30 行)

```python
import argparse
from api import call_api
from tool import execute_tool
from prompt import get_system_prompt
from context import Context
from project import scan_project
import json

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--task", required=True)
    parser.add_argument("--project", default=".")
    parser.add_argument("--config", default="config.json")
    args = parser.parse_args()
    
    config = json.load(open(args.config))
    ctx = Context(max_history=config.get("max_history", 20))
    project_info = scan_project(args.project)
    
    for i in range(config.get("max_loops", 5)):
        messages = ctx.build(get_system_prompt(), project_info)
        messages.append({"role": "user", "content": args.task})
        
        response = call_api(messages, config)
        result = execute_tool(response)
        
        if result.done:
            print(result.output)
            break
        
        ctx.add("assistant", response)
        ctx.add("system", f"执行结果:\n{result.output}")
    else:
        print("未在限定次数内完成任务")

if __name__ == "__main__":
    main()
```

#### 其他模块

- **api.py**: API 调用封装
- **prompt.py**: 提示词管理
- **tool.py**: 工具解析与执行
- **context.py**: 上下文管理
- **project.py**: 项目扫描

---

> **核心思路**：去掉 OpenCode 的 TUI 交互界面，只保留 CLI 参数调用 + 提示词调优。LLM 返回什么就执行什么，执行结果放回上下文继续调用，直到完成或次数用尽。

---

## 使用

```bash
python opencode.py "给用户模块添加缓存"
```

---

## 代码结构

```
opencode.py
├── parse_tags()      # 解析标签
├── execute_tag()     # 执行标签逻辑
├── build_context()   # 生成上下文
└── call_api()       # 调用远程 API
```

---

## 核心优势

- **极简**：无需复杂架构，标签 + 执行器 = 200 行
- **通用**：任何支持文本输出的 API 都能用
- **可扩展**：新增标签只需添加对应执行逻辑
- **自我更新**：脚本可以修改自己
