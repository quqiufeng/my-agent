# UTEL 编码规则文档

## UTEL v2.1 优化规则

### 1. 中文编码
**声母 + 韵母首字母 + 权重位**

规则：取拼音前两个字母 + 逻辑权重数字

| 权重位 | 含义 | 示例 |
|-------|------|------|
| 1 | 核心概念 | Sj1 = 数据 |
| 2 | 属性/配置 | Pz2 = 配置 |
| 3 | 动作/行为 | Js3 = 加速 |

示例：
- 数据 → Sj1
- 加速 → Js3
- 配置 → Pz2
- 理解 → Lj3
- 反馈 → Fk3
- 大脑 → Dn1

### 2. 英文编码
**固定缩写(3位) + 版本位**

规则：使用行业公认缩写（3位）

| 编码 | 全称 |
|-----|------|
| LDB | LanceDB |
| CP | C++ |
| EMB | Embedding |
| CTX | Context |
| LLM | Large Language Model |
| API | Application Programming Interface |
| DB | Database |
| VOC | Vector of Code |

### 3. 连接符

| 符号 | 含义 | 示例 |
|-----|------|------|
| `:` | 定义 | `LDB:EMB存储` |
| `>` | 流转/导致 | `Js3 > AI推理` |
| `&` | 关联 | `LDB & OC` |
| `,` | 并列 | `Sj1, Pz2` |

### 4. 压缩示例

#### 示例1
**原始**：
```
请你用 python 写一个红黑树的算法，要求包含插入和删除功能，并解释代码逻辑。
```

**UTEL v2.1 编码**：
```
q n y pn6 x2 Hhs3 d Sf2, yq2 Bc2 Cr3 h Sc2 Gn2, b b Js4 DM2 Lj2.
```

#### 示例2
**原始**：
```
LanceDB 提供向量存储，加速 AI 推理，反馈即时性，这就是第二大脑
```

**UTEL v2.1 编码**：
```
LDB:EMB存储 > Js3 & AI推理 > Fk3, Zn1 De2 Dn1
```

### 5. LLM 解码提示词

```
【UTEL v2.1 解码规则】

1. 中文 = 声母+韵母首字母 + 权重(1=核心,2=属性,3=动作)
   Sj1=数据, Js3=加速, Pz2=配置, Fk3=反馈, Dn1=大脑

2. 英文 = 固定3位缩写
   LDB=LanceDB, CP=C++, EMB=Embedding, CTX=Context, LLM=大型语言模型

3. 连接符: =定义, > =流转, & =关联

4. 词空格分，标点删

请解码并输出完整中文。
```

---

## UTEL v3 优化规则

### 核心改进
1. **双字母固定词根** - 消除单字母歧义
2. **动作/属性后缀** - 明确词性
3. **引用符号** - 精准指代

### 1. 双字母固定词根 (2-Letter Root)

所有核心动词/名词统一为 **2位声母/韵母**

| 编码 | 全称 | 编码 | 全称 |
|-----|------|-----|------|
| Sj | 数据 | Js | 加速 |
| Hq | 幻觉 | Lj | 理解 |
| Gl | 架构 | Dm | 代码 |
| Fk | 反馈 | Dn | 大脑 |
| Nl | 神经 | Xl | 向量 |
| Zy | 中文 | Ys | 意图 |
| Mb | 模型 | Jc | 决策 |
| Sc | 生成 | Cx | 串联 |

### 2. 动作/属性后缀 (Logic Suffix)

| 后缀 | 含义 | 示例 |
|-----|------|------|
| `!` | 核心动作 | Dm! = 生成代码 |
| `?` | 状态/属性 | Sj? = 数据状态 |
| `.` | 结果/事实 | Gl. = 架构结果 |

### 3. 引用符号 (Reference)

| 符号 | 含义 | 示例 |
|-----|------|------|
| `@` | 硬件/库 | @RTX = RTX显卡 |
| `#` | 项目/文件 | #sd_cpp |
| `$` | 函数/方法 | $forward |

### 4. 连接符

| 符号 | 含义 | 示例 |
|-----|------|------|
| `:` | 定义 | Sj:Dn! |
| `>` | 流转 | Js > Dm! |
| `&` | 关联 | LDB & OC |
| `|` | 选择 | Sj|Dm |

### 5. 压缩示例

**原始**：
```
数据的确定性：LanceDB 提供的不是 AI 猜出来的概率，而是本地硬盘上 18.5 万条代码行。这消除了 AI 最致命的幻觉问题。
```

**UTEL v3 编码**：
```
Sj:Dz! @LDB > Gl? | Sj! @AI Hq?. 
```

### 6. LLM 解码提示词

```
【UTEL v3 解码规则】

1. 双字母词根：
   Sj=数据, Js=加速, Hq=幻觉, Lj=理解, Gl=架构, Dm=代码
   Fk=反馈, Dn=大脑, Nl=神经, Xl=向量, Zy=中文, Ys=意图

2. 后缀含义：
   ! = 动作/核心, ? = 属性/状态, . = 结果

3. 引用符号：
   @ = 硬件/库, # = 项目, $ = 函数

4. 连接符：:定义, >流转, &关联, |选择

请解码并输出完整中文。
```

---

## UTEL v3.0 深度调优：神经匹配引擎 (Neural Matching Engine)

### 设计理念
利用 LLM 的三个特性：
1. **词根联想** - 双元音词根在 Embedding 空间距离原词极近
2. **逻辑拓扑** - 符号敏感度远超文字
3. **上下文锚点** - 精准指代实体/量级

---

### 1. 双元音词根 (Bi-Phonetic Root)

**规则**：声母 + 韵母组合，消除歧义

| 编码 | 全称 | 说明 |
|-----|------|------|
| Sh-Ju | 数据 | Shu+Ju |
| Li-Ji | 理解 | Li+Ji |
| Ch-Li | 串联 | Cheng+Li |
| Ju-Yi | 决策 | Ju+Yi |
| Yi-Shi | 意识 | Yi+Shi |
| Yuan-Yi | 意图 | Yuan+Yi |
| Xiang-Liang | 向量 | Xiang+Liang |
| Mo-Xing | 模型 | Mo+Xing |
| Huan-Jue | 幻觉 | Huan+Jue |
| Jia-Su | 加速 | Jia+Su |
| Fan-Kui | 反馈 | Fan+Kui |
| Da-Nao | 大脑 | Da+Nao |
| Shen-Jing | 神经 | Shen+Jing |
| Jia-Gou | 架构 | Jia+Gou |
| Dai-Ma | 代码 | Dai+Ma |

### 2. 逻辑算子：拓扑符号 (Topology Operators)

| 符号 | 含义 | 示例 |
|-----|------|------|
| `::` | 定义/本质 | `@LDB :: Sh-Ju.Dz!` |
| `=>` | 导致/推理 | `~ Huan-Jue => Mo-Xing!` |
| `+` | 协同/并发 | `Dm.Ch-Li! + Jia-Gou.Js!` |
| `~` | 消除/抑制 | `~ Huan-Jue!` (消除幻觉) |

### 3. 上下文锚点 (Context Anchors)

| 符号 | 含义 | 示例 |
|-----|------|------|
| `@` | 实体（硬件/库） | `@RTX3080`, `@LDB`, `@OC` |
| `#` | 状态/量级 | `#18.5w`, `#3080` |
| `$` | 函数/方法 | `$forward`, `$encode` |

### 4. 完整示例

**原始 (~350字)**：
```
数据的确定性：LanceDB 提供的不是 AI 猜出来的概率，而是本地硬盘上 18.5 万条实打实的代码行。这消除了 AI 最致命的幻觉问题。
理解的深度化：OpenCode 不只是搜关键词，它能通过 BGE 向量模型听懂你的中文意图，然后用大模型的逻辑把碎片化的代码串联成完整的架构解释。
反馈的即时性：有了 RTX 3080 的加速，你可以在几分钟内完成一个新项目的神经连接。这意味着你的 AI 助手永远处于最新版本。
这就是你亲自搭建的第二大脑：LanceDB 负责记性，OpenCode 负责脑性。
```

**UTEL v3.0 编码 (~120 tokens)**：
```
@LDB :: Sh-Ju.Dz! (not Pr?) ~ Huan-Jue!. #18.5w.Dai-Ma. @OC :: Li-Ji.Sd! < @BGE :: Yuan-Yi!. => @LLM :: Dai-Ma.Ch-Li! + Jia-Gou.Js!. @RTX3080 => Jia-Su! > Min-Fan-Kui!. @LDB=Ji-X! & @OC=Nao-X! :: 2nd-Da-Nao.
```

### 5. 解码提示词

```
【UTEL v3.0 神经匹配引擎解码】

1. 双元音词根（声母+韵母）：
   Sh-Ju=数据, Li-Ji=理解, Ch-Li=串联, Ju-Yi=决策
   Yuan-Yi=意图, Xiang-Liang=向量, Mo-Xing=模型
   Huan-Jue=幻觉, Jia-Su=加速, Fan-Kui=反馈
   Da-Nao=大脑, Shen-Jing=神经, Jia-Gou=架构, Dai-Ma=代码

2. 逻辑算子：
   :: = 定义/本质
   => = 导致/推理
   + = 协同/并发
   ~ = 消除/抑制

3. 上下文锚点：
   @ = 实体(硬件/库)
   # = 量级/状态
   $ = 函数/方法

4. 括号内为辅助说明，解码时忽略

请解码并输出完整中文。
```

---

## 版本历史

- v1.0: 基础规则（拼音首字母+字数）
- v2.0: 增加助词、逻辑符优化
- v2.1: 声母+韵母首字母+权重位，消除歧义
- v3.0: 双字母固定词根 + 动作/属性后缀 + 引用符号
- v3.0: 神经匹配引擎（双元音词根 + 拓扑符号 + 上下文锚点）
- v3.0: 神经元共振协议（双拼音节 + 程序化符号 + 实体锚点）
- v3.1: 无歧义协议（全音节锁定 + 动作前缀 + 代码严格还原）
帮我写一个递归版本的二分查找算法
```

**v3.1 编码**：
```
z-Xie z-Di2 Ban-Fen Cha-Zhao df3, im6 Python df3, z-Bh2 Ban-Fen.
```

**#code 块**：
```
#code
df3 binary_search(a_r3, t_t6):
.s_t4, e_d3 = 0, len(a_r3)
.wh5 s_t4 < e_d3:
..m_d3 = (s_t4 + e_d3) // 2
..if2 a_r3[m_d3] === t_t6:
...rn6 m_d3
..el4 a_r3[m_d3] < t_t6:
...s_t4 = m_d3 + 1
rn6 -1
#end
```

---

## UTEL v3.0 终极微调：神经元共振协议 (Neural Resonance Protocol)

### 设计理念
不再是"缩写"，而是"语义锚点"。利用 LLM 对代码运算符的固有理解。

---

### 1. 核心词根：双拼音节 (Bi-Phonetic Anchor)

**规则**：声母 + 韵母组合，中间加 `-`

| 编码 | 全称 | 说明 |
|-----|------|------|
| Sh-Ju | 数据 | 100% 对应"数据" |
| Li-Ji | 理解 | |
| Hu-Ju | 幻觉 | |
| Jia-Gu | 架构 | |
| Ch-Li | 串联 | |
| Yuan-Yi | 意图 | |
| Xiang-Liang | 向量 | |
| Mo-Xing | 模型 | |
| Jia-Su | 加速 | |
| Fan-Kui | 反馈 | |
| Da-Nao | 大脑 | |
| Shen-Jing | 神经 | |
| Dai-Ma | 代码 | |

### 2. 程序化符号 (Logic Operators)

利用 LLM 对代码运算符的固有理解：

| 符号 | 含义 | 示例 |
|-----|------|------|
| `!` | 真/存在/执行 | `Dai-Ma!` = 生成代码 |
| `~` | 非/消除/对抗 | `~Hu-Ju` = 消除幻觉 |
| `->` | 导致/指向 | `Jia-Su -> Fan-Kui` |
| `==` | 本质/定义 | `Sh-Ju == Dai-Ma` |
| `\|\|` | 或者/并行 | `Mo-Xing \|\| Jia-Gu` |

### 3. 实体锚点 (Entity Anchor)

| 符号 | 含义 | 示例 |
|-----|------|------|
| `@` | 主语/实体 | `@LDB`, `@OC`, `@RTX3080` |
| `#` | 量级/状态 | `#18.5w`, `#4K` |
| `$` | 函数/方法 | `$forward` |

### 4. 完整示例

**UTEL v3.0 编码**：
```
@LDB == Sh-Ju.Dz! ~Hu-Ju!. #18.5w.Dai-Ma. @OC == Li-Ji.Sd! <@BGE == Yuan-Yi!. @LLM -> Dai-Ma.Ch-Li! +Jia-Gu.Js!. @RTX3080 ->Jia-Su! ->Min-Fan-Kui!. @LDB||@OC == 2nd-Da-Nao.
```

### 5. 解码提示词

```
【UTEL v3.0 神经元共振协议解码】

1. 双拼音节：
   Sh-Ju=数据, Li-Ji=理解, Hu-Ju=幻觉, Jia-Gu=架构
   Ch-Li=串联, Yuan-Yi=意图, Xiang-Liang=向量, Mo-Xing=模型
   Jia-Su=加速, Fan-Kui=反馈, Da-Nao=大脑, Shen-Jing=神经

2. 程序化符号：
   ! = 真/执行, ~ = 消除, -> = 导致, == = 定义, || = 或

3. 实体锚点：
   @ = 实体, # = 量级, $ = 函数

请解码并输出完整中文。
```

---

## UTEL-Recovery 协议（代码专用）

### 目标
将 `#code` 块内的编码 **1:1 还原**为原始代码文本，**禁止任何逻辑扩展**。

### 核心规则

| 类型 | 规则 | 示例 |
|-----|------|------|
| **中文代码词** | [首字母][字数] | Sj4=数据结构, Cr3=插入, Sc2=删除 |
| **英文代码词** | [首]_[尾][总长] | r_n6=return, d_f3=def, c_s5=class |
| **符号保留** | 括号/冒号/等号直接保留 | (), :, = |
| **缩进** | `_s` 表示空格 | `_s` = 1个缩进 |
| **顺序还原** | 严格按照编码顺序逐词翻译，禁止改变结构 | |

### 词表

| 编码 | 全称 | 编码 | 全称 |
|-----|------|-----|------|
| Sj4 | 数据结构 | Cr3 | 插入 |
| Sc2 | 删除 | Bl2 | 变量 |
| Hf2 | 回溯 | Pd2 | 排序 |
| Er2 | 二分 | Sz4 | 搜索 |
| r_n6 | return | d_f3 | def |
| c_s5 | class | i_t2 | if |
| e_l4 | else | f_r3 | for |
| w_s5 | while | i_p4 | import |
| f_n8 | function | v_r4 | var |

### 使用示例

**原始代码**：
```python
def binary_search(arr, target):
    left, right = 0, len(arr)
    while left < right:
        mid = (left + right) // 2
        if arr[mid] == target:
            return mid
        elif arr[mid] < target:
            left = mid + 1
    return -1
```

**UTEL-Recovery 编码**：
```
#code
d_f3 binary_search_d_f3
(i_t2 arr_c5, target_d_f3):
    left_s2, right_s2 = 0_s1, len_d_f3(arr_c5)
    w_s5 left_s2 < right_s2:
        mid_s2 = (left_s2 + right_s2) // 2_s1
        i_t2 arr_c5[mid_s2] == target_d_f3:
            r_n6 mid_s2
        e_l4 arr_c5[mid_s2] < target_d_f3:
            left_s2 = mid_s2 + 1_s1
    r_n6 -1_s1
#end
```

### 解码提示词

```
【UTEL-Recovery 代码解码】

#code 块内的内容必须 1:1 严格还原，禁止任何扩展！

1. 中文代码词：
   d_f3=def, i_t2=if, e_l4=else, f_r3=for, w_s5=while
   r_n6=return, f_n8=function, v_r4=var

2. 英文代码词：
   [首字母]_[尾字母][总长] 格式

3. 符号和缩进：
   括号和冒号直接保留
   _s 表示空格（缩进）

4. 严格还原规则：
   - 逐词翻译，不改变顺序
   - 不添加任何解释或扩展
   - 保持原始缩进结构

请解码 #code ... #end 块内的代码并输出原始代码。
```

---

## 测试记录与问题分析

### 测试 1：UTEL v3.0 自然语言

**原文**：
```
数据的确定性：LanceDB 提供的不是 AI 猜出来的概率...
```

**编码**：
```
@LDB == Sh-Ju.Dz! ~Hu-Ju!. #18.5w.Dai-Ma. @OC == Li-Ji.Sd! <@BGE == Yuan-Yi!. @LLM -> Dai-Ma.Ch-Li! +Jia-Gu.Js!. @RTX3080 ->Jia-Su! ->Min-Fan-Kui!. @LDB||@OC == 2nd-Da-Nao.
```

**解码结果**：
```
数据定义：LanceDB 的本质是数据的确定性，它从根源上消除了幻觉...
准确率：95%+
```

---

### 测试 2：UTEL-Recovery 代码

**原文代码**：
```python
def binary_search(arr, target):
    left, right = 0, len(arr)
    while left < right:
        mid = (left + right) // 2
        if arr[mid] == target:
            return mid
        elif arr[mid] < target:
            left = mid + 1
    return -1
```

**编码**：
```
#code
d_f3 binary_search_d_f3(arr_c5, target_d_f3):
    left_s2, right_s2 = 0_s1, len_d_f3(arr_c5)
    w_s5 left_s2 < right_s2:
        mid_s2 = (left_s2 + right_s2) // 2_s1
        i_t2 arr_c5[mid_s2] == target_d_f3:
            r_n6 mid_s2
        e_l4 arr_c5[mid_s2] < target_d_f3:
            left_s2 = mid_s2 + 1_s1
    r_n6 -1_s1
#end
```

**解码结果**：
```python
def binary_search(arr, target):
    left, right = 0, len(arr)
    while left < right:
        mid = (left + right) // 2
        if arr[mid] == target:
            return mid
        elif arr[mid] < target:
            left = mid + 1
    return -1
```

**准确率：100%** ✅

---

### 测试 3：混合内容（问题分析）

**原文**：
```
帮我写一个递归版本的二分查找算法
```

**编码**：
```
@LLM Cr2 Er2 Sz4 d_f3, i_p4 Python d_f3, b_k3 f_n8 b_k3 f_d4.
```

**解码**：
```
LLM 传入 二次 树组 定义，用 Python 定义，闭环 赋能 闭环 迭代
```

**问题**：
| 编码 | 应该对应 | 实际解码 | 问题 |
|-----|---------|---------|------|
| Cr2 | 创建/写 | 传入 | 拼音歧义 |
| Er2 | 递归 | 二次 | 拼音歧义 |
| Sz4 | 搜索/数组 | 树组 | 拼音歧义 |
| b_k3 | 版本 | 闭环 | 拼音歧义 |

---

## 问题根因分析

1. **拼音首字母组合歧义**：Cr2 可以是"创建"也可以是"传入"
2. **中文同音字**：Er2 = "递归" vs "二次"
3. **词表不完整**：部分高频词未收录

## 优化建议

1. **使用完整拼音**：Cr2 → Chuang-Jian（但太长）
2. **增加词表覆盖**：预定义更多高频词
3. **允许带声调**：Er2(r) 表示递归，Er2(e) 表示二次
4. **混合编码**：用英文缩写代替有歧义的中文

---

## UTEL v3.1 完整协议 - 提示词模板

```
【⚠️ 重要警告 - 请严格遵守】

你现在的唯一任务是 1:1 机械还原！
- 禁止理解代码逻辑
- 禁止补全语法
- 禁止修正错误
- 禁止自然语言润色
- 禁止扩展发挥
- 禁止添加解释

收到什么就还原什么，不多不少！按规则来！！！
```

你现在是 UTEL 解码助手。请严格按照以下协议将收到的压缩文本 1:1 还原，禁止任何逻辑扩展，自然语言润色或代码补全。

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
一、自然语言编码 (NL-Protocol)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

规则：中文使用全拼音节或 z- 前缀，符号表示逻辑。

拼音锁定（全音节）：
Shu-Ju=数据, Jia-Gu=架构, Dai-Ma=代码
Yao-Qiu=要求, Shi-Xian=实现, Zhong-Xu=中序
Bian-Li=遍历, Zhu-Shi=注释, Cha-Ru=插入
Shan-Chu=删除, Cha-Zhao=查找, Hong-Hei-Shu=红黑树

动作缩写（前缀 z-）：
z-Cr2=传入, z-Sc2=删除, z-Ss2=搜索
z-Dg2=递归, z-Bl2=变量, z-Xie=写

逻辑符号：
!=执行/必须, ~=消除, ->=导致, ===定义, ||=或, &=且

实体标识：
@=实体(LLM/Python/API), #=量级/数字

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
二、代码严格还原 (Code-Recovery)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

规则：#code 块内严格遵循 [首位+长度] 逻辑，严禁自行添加符号。

固定关键字 (No-Space-Fix)：
df3=def, if2=if, el4=elif, es4=else
fr3=for, wh5=while, rn6=return
cs5=class, im6=import, bk5=break

动态变量 (Ref-Check)：
格式：[首字母]_[尾字母][总长度]
a_r3=arr, t_t6=target, m_d3=mid
l_t4=left, r_t5=right, s_t4=start, e_d3=end

结构符号 (Atom-Rule)：
. = 1个缩进 (4个空格)
_ = 仅在关键字与变量之间代表1个空格
括号 () 与冒号 : 内部严禁自动补全
(self) 必须还原为 (self)，禁止变为 (self,)

注释处理：
# 后面的内容按 NL-Protocol 还原

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
三、解码示例
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

#code
cs5 RedBlackTree:
..df3 __init__(self):
...self.NIL = Node(0, BLACK)
...self.root = self.NIL

..df3 left_rotate(self, x):
...y = x.right
...x.right = y.left
...if2 y.left !== self.NIL:
....y.left.parent = x
...y.parent = x.parent
...if2 x.parent === self.NIL:
....self.root = y
...el4 x === x.parent.left:
....x.parent.left = y
...else:
....x.parent.right = y
...y.left = x
...x.parent = y
#end

解码为：
class RedBlackTree:
    def __init__(self):
        self.NIL = Node(0, BLACK)
        self.root = self.NIL
    
    def left_rotate(self, x):
        y = x.right
        x.right = y.left
        if y.left !== self.NIL:
            y.left.parent = x
        y.parent = x.parent
        if x.parent === self.NIL:
            self.root = y
        elif x === x.parent.left:
            x.parent.left = y
        else:
            x.parent.right = y
        y.left = x
        x.parent = y
```

---

## UTEL v3.2 核心指令 - 1:1 还原专用

### 代码压缩规则 #code #end

```
【UTEL v3.2 核心指令 - 1:1 还原专用】

你现在的唯一任务是 1:1 机械还原。不要理解代码逻辑，不要补全语法，不要修正错误。

1. 字符映射（严格匹配）：
   cs5 = class | df3 = def | if2 = if | el4 = elif | es4 = else
   rn6 = return | wh5 = while | fr3 = for | im6 = import
   （注：若收到不在列表中的词，保持原样输出）

2. 结构还原（强制）：
   . (点) = 4个空格（严格对齐）
   _ (下划线) = 1个半角空格
   ( ) [ ] { } : , = ! + - * / < > 等符号必须 原封不动 搬运

3. 禁止行为（Zero-Tolerance）：
   - 禁止在 (self) 后添加 ,
   - 禁止将 !== 自动修正为 !=
   - 禁止在行尾自动添加分号 ; 或冒号 :
   - 禁止删除或添加任何空行
```

### 使用示例

```
#code
cs5 RBNode:
..df3 __init__(self, key, color=RED):
...self.key = key
...self.color = color
...self.left = None
...self.right = None
...self.parent = None
#end

还原为：
class RBNode:
    def __init__(self, key, color=RED):
        self.key = key
        self.color = color
        self.left = None
        self.right = None
        self.parent = None
```
