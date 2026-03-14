# Code AI Tools - 本地代码向量知识库

基于 **LanceDB + OpenCode MCP** 构建的本地代码语义检索系统，为 AI 编程助手提供"过目不忘"的能力。

---

## 目录

- [核心价值](#核心价值)
- [技术架构](#技术架构)
- [系统要求](#系统要求)
- [快速开始](#快速开始)
- [功能模块详解](#功能模块详解)
- [高级配置](#高级配置)
- [集成 OpenCode](#集成-opencode)
- [进阶使用](#进阶使用)
- [故障排查](#故障排查)
- [工业应用价值](#工业应用价值)

---

## 核心价值

### 解决 AI 幻觉和知识陈旧问题

| 传统方式 | 本方案 |
|---------|--------|
| AI 靠记忆猜测代码 | 基于真实代码向量检索 |
| 无法处理私有项目 | 本地索引，隐私安全 |
| 知识截止训练日期 | 实时索引最新代码 |
| 可能产生幻觉 | 100% 基于事实检索 |

### 典型应用场景

1. **私有代码库问答** - 询问公司内部项目的实现细节
2. **遗留代码理解** - 分析老项目的架构设计
3. **快速定位 Bug** - 根据错误描述检索相关代码
4. **学习开源项目** - 分析 stable-diffusion.cpp 等大型项目

---

## 技术架构

```
┌─────────────────────────────────────────────────────────────────┐
│                        OpenCode (AI 编程助手)                    │
└─────────────────────────┬───────────────────────────────────────┘
                          │ MCP Protocol
┌─────────────────────────▼───────────────────────────────────────┐
│                    mcp_lancedb_server.py                        │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  search_code(project_id, query)                         │   │
│  │  - 连接 LanceDB                                         │   │
│  │  - 向量化查询词                                          │   │
│  │  - 向量相似度检索                                        │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────┬───────────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────────────┐
│                   LanceDB (向量数据库)                           │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │ sd_cpp.lance│  │ proj2.lance│  │ proj3.lance│  ...         │
│  │ (18.5万条)  │  │             │  │             │              │
│  └─────────────┘  └─────────────┘  └─────────────┘              │
└─────────────────────────┬───────────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────────────┐
│               index_lancedb.py (索引器)                           │
│  - 扫描代码文件                                                  │
│  - 递归分块 (chunk_size=1000, overlap=150)                     │
│  - BGE 向量化 (GPU 加速)                                        │
│  - 批量写入 LanceDB                                             │
└─────────────────────────────────────────────────────────────────┘
```

### 技术选型理由

| 组件 | 选择 | 理由 |
|------|------|------|
| 向量数据库 | **LanceDB** | 基于 Rust + Lance 格式，写入即落盘，无 SQLite 持久化 bug |
| Embedding | **BAAI/bge-small-zh-v1.5** | 中英文双语支持，体积小(80MB)，精度优秀 |
| 协议层 | **FastMCP** | 轻量级 MCP 实现，与 OpenCode 无缝集成 |
| GPU 加速 | **RTX 3080+** | 18万条数据 6分钟完成索引 (vs CPU 30+ 小时) |

---

## 系统要求

### 硬件环境

- **GPU**: NVIDIA RTX 3080+ (10GB+ 显存)
- **内存**: 16GB+ RAM
- **存储**: 50GB+ SSD

### 软件环境

- **操作系统**: Ubuntu 22.04+
- **Python**: 3.10+
- **CUDA**: 11.8+

---

## 快速开始

### 1. 安装依赖

```bash
cd ~/my-agent/code_ai_tools
pip install -r requirements.txt
```

### 2. 索引代码项目

```bash
python3 index_lancedb.py ~/stable-diffusion.cpp sd_cpp
```

**参数说明**:
- 第1个参数: 代码仓库绝对路径
- 第2个参数: 项目标识符 (用于后续查询)

**后台运行**:
```bash
nohup python3 index_lancedb.py ~/stable-diffusion.cpp sd_cpp > index.log 2>&1 &
```

### 3. 测试检索

```bash
python3 query_lancedb.py sd_cpp "UNet前向传播实现"
```

### 4. 启动 MCP 服务

```bash
python3 mcp_lancedb_server.py
```

---

## 功能模块详解

### 1. index_lancedb.py - 高性能索引器

**核心功能**:
- 递归扫描 C++/C 代码文件
- 智能分块 (chunk_size=1000, overlap=150)
- GPU 加速向量化
- 分批写入 LanceDB

**关键参数**:
```python
CHUNK_SIZE = 1000    # 每个代码块的最大字符数
OVERLAP = 150         # 相邻块之间的重叠字符数
BATCH_SIZE = 10000    # GPU 向量化批次大小
```

**向量维度**: 512 (BGE-small 模型输出)

### 2. query_lancedb.py - 检索测试工具

**用法**:
```bash
python3 query_lancedb.py <project_id> <query> [--top-k 3]
```

**示例**:
```bash
# 查询 UNet 实现
python3 query_lancedb.py sd_cpp "UNet前向传播"

# 指定返回条数
python3 query_lancedb.py sd_cpp "VAE解码器" --top-k 5
```

### 3. mcp_lancedb_server.py - MCP 服务端

**暴露工具**:
```python
@mcp.tool()
def search_code(project_id: str = "sd_cpp", query: str = "", top_k: int = 3) -> str:
    """
    在指定项目的代码库中检索相关代码片段
    
    参数:
        project_id: 项目标识符 (如 sd_cpp, my_project)
        query: 查询内容 (支持中英文)
        top_k: 返回结果数量 (默认3)
    
    返回:
        格式化的代码片段，包含文件名和代码内容
    """
```

---

## 高级配置

### 目录分离架构 (数据与脚本分离)

本方案支持将**向量数据库**和**脚本工具**分离，便于数据迁移和备份。

#### 默认目录结构

```
~/
├── lancedb_data/        # 向量数据库 (可移动、可备份)
│   ├── sd_cpp.lance    # 项目A索引
│   ├── llama_cpp.lance # 项目B索引
│   └── ...
│
└── my-agent/code_ai_tools/       # 脚本工具 (可版本控制)
    ├── index_lancedb.py
    ├── query_lancedb.py
    ├── mcp_lancedb_server.py
    └── README.md
```

#### 自定义数据库路径

如果希望将数据库存放到其他位置，修改各脚本中的 `DB_PATH`:

```python
# 在 index_lancedb.py, query_lancedb.py, mcp_lancedb_server.py 中修改:
DB_PATH = os.path.expanduser("/path/to/your/lancedb_data")
```

#### 数据迁移示例

```bash
# 1. 备份数据库
cp -r ~/lancedb_data /mnt/backup/lancedb_data_$(date +%Y%m%d)

# 2. 迁移到新机器
scp -r ~/lancedb_data user@new-machine:~/

# 3. 在新机器修改脚本路径后即可使用
```

#### 目录分离的优势

| 优势 | 说明 |
|-----|------|
| **数据独立** | 数据库可独立备份、迁移、共享 |
| **脚本可版本控制** | 代码工具可提交到 Git |
| **多数据集共享** | 同一脚本可切换不同数据库目录 |
| **节省空间** | 可将大数据盘挂载到其他位置 |

### 索引更多项目

```bash
# 索引另一个项目
python3 index_lancedb.py ~/llama.cpp llama_cpp

# 索引 Python 项目
python3 index_lancedb.py ~/my_project my_proj
```

### 多项目同时索引

```bash
# 批量索引脚本
for repo in stable-diffusion.cpp llama.cpp whisper.cpp; do
    python3 index_lancedb.py ~/$repo ${repo%.cpp} &
done
wait
```

### 使用其他 Embedding 模型

修改 `index_lancedb.py` 中的模型配置:

```python
# 中文支持更好的模型
model_name="BAAI/bge-base-zh-v1.5"

# 英文为主
model_name="sentence-transformers/all-MiniLM-L6-v2"
```

---

## 集成 OpenCode

### 配置 MCP 节点

编辑 `~/.config/opencode/opencode.json`:

```json
{
  "mcp": {
    "minimax-tools": {
      "type": "local",
      "command": ["uvx", "minimax-coding-plan-mcp", "-y"],
      "environment": {
        "MINIMAX_API_KEY": "your-api-key"
      },
      "enabled": true
    },
    "code-search": {
      "type": "local",
      "command": ["python3", "/home/dministrator/my-agent/code_ai_tools/mcp_lancedb_server.py"],
      "enabled": true
    }
  }
}
```

### 重启 OpenCode

```bash
# 重启 OpenCode 使配置生效
# 然后可以直接对话询问代码问题
```

### 使用示例

```
用户: 在 sd_cpp 项目中，UNet 是如何进行 CPU/GPU 混合推理的？

OpenCode 调用: search_code(project_id="sd_cpp", query="CPU GPU 混合推理 内存优化")

返回:
--- 结果 1 (src/sd.cpp:245) ---
void sd_gpu_offload() {
    // 模型权重卸载逻辑
    for (auto& layer : layers) {
        offload_params_to_cpu(layer);
    }
}
...
```

---

## 进阶使用

### 符号链接多项目管理

将其他项目的代码链接到统一目录:

```bash
mkdir -p ~/my-agent/code_ai_tools/indexed_repos

ln -s /mnt/data/other_project ~/my-agent/code_ai_tools/indexed_repos/other_proj

python3 index_lancedb.py ~/my-agent/code_ai_tools/indexed_repos/other_proj other_proj
```

### 更新索引

重新运行索引命令会自动覆盖:

```bash
python3 index_lancedb.py ~/stable-diffusion.cpp sd_cpp
```

### 查看已索引项目

```python
import lancedb
db = lancedb.connect("~/my-agent/code_ai_tools/lancedb_data")
for table in db.list_tables():
    print(f"{table.name}: {table.count_rows()} 条")
```

---

## 故障排查

### 问题1: CUDA 不可用

**症状**: `RuntimeError: CUDA not available`

**解决**:
```bash
# 检查 CUDA
python3 -c "import torch; print(torch.cuda.is_available())"

# 安装 CUDA 版 PyTorch
pip install torch --index-url https://download.pytorch.org
```

### 问题2: 索引速度慢

**原因**: 使用 CPU 而非 GPU

**解决**:
```bash
# 确认 GPU 可用后重新索引
python3 index_lancedb.py ~/your_project project_id
```

### 问题3: 检索结果为空

**检查**:
```bash
# 确认索引存在
python3 -c "
import lancedb
db = lancedb.connect('~/my-agent/code_ai_tools/lancedb_data')
print(db.list_tables())
"
```

---

## 工业应用价值

### 为什么这个架构有极高的工业价值

#### 1. 彻底解决 AI 幻觉

- **传统 RAG**: 依赖外部 API，数据隐私有风险
- **本地向量库**: 数据不出本地，零隐私泄露风险
- **100% 事实检索**: 基于真实代码，无编造成分

#### 2. 知识实时更新

| 方案 | 知识更新时间 |
|------|-------------|
| 训练大模型 | 数周-数月 |
| 微调 | 数天 |
| 本地向量库 | **数分钟** |

#### 3. 降本增效

- **硬件要求低**: RTX 3080 即可运行
- **零 API 成本**: 离线部署，无需付费 API
- **维护简单**: 单一 Python 脚本

#### 4. 私有化部署

- 适用于企业内部知识库
- 符合数据合规要求
- 可集成到 IDE (VSCode, JetBrains)

### 扩展方向

1. **多模态检索**: 支持图片、文档检索
2. **增量索引**: 监听文件变化自动更新
3. **分布式部署**: LanceDB 支持远程模式
4. **混合检索**: 结合关键词和向量检索

---

## 文件结构

```
~/my-agent/code_ai_tools/
├── index_lancedb.py       # 索引器 (GPU加速版)
├── query_lancedb.py        # 检索测试工具
├── mcp_lancedb_server.py  # MCP 服务端
├── requirements.txt       # Python 依赖
├── lancedb_data/          # 向量数据库目录
│   ├── sd_cpp.lance     # stable-diffusion.cpp 索引
│   └── ...
└── index.log             # 索引日志
```

---

## 性能基准

| 指标 | 数值 |
|------|------|
| 索引速度 (RTX 3080) | ~30,000 条/分钟 |
| 查询响应时间 | < 1 秒 |
| 向量维度 | 512 |
| 支持最大项目 | 无限制 (取决于磁盘) |
| 内存占用 (索引时) | ~2GB GPU + 4GB RAM |

---

## Prompt 压缩规则

详见 [rule.md](../rule.md)

---

## 许可证

MIT License - 可自由用于商业和非商业项目。

---

**维护者**: Code AI Tools  
**版本**: 1.0.0  
**更新日期**: 2024
