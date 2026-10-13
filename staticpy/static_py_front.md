# StaticPy — AI Agent 的机器学习编译语言

> **StaticPy 是面向 AI Agent 的机器学习开发语言。**
> 用 Python 语法子集编写算法流程，通过 AOT 编译生成独立 ELF 二进制。
> 性能敏感部分下沉到 C/C++ helper 运行时，训练/推理代码直接变成可部署程序。
> 无 Python 解释器、无 pip、无 venv、无 GIL。

---

## 目录

1. [定位与愿景](#一定位与愿景)
2. [核心设计原则](#二核心设计原则)
3. [核心文件职责](#三核心文件职责)
4. [打包 ELF 流水线](#四打包-elf-流水线)
5. [运行时加载外部 .so](#五运行时加载外部-so)
6. [支持的 Python 子集](#六支持的-python-子集)
7. [类型系统](#七类型系统)
8. [AI 项目模板](#八ai-项目模板)
9. [编写 C/C++ Helper](#九编写-cc-helper)
10. [最小示例](#十最小示例)
11. [调试与错误](#十一调试与错误)
12. [一句话总结](#十二一句话总结)

---

## 一、定位与愿景

### 1.1 目标用户

StaticPy 的首要用户是 **AI Agent**，其次是需要把算法固化成原生二进制的人类开发者。

AI Agent 使用 StaticPy 时，只需关注：
- 算法结构（网络、损失、训练循环、推理逻辑）
- 调用已有算子（通过 `extern fn`）
- 编译并运行 ELF

不需要关注：
- Python 环境配置
- pip 依赖冲突
- venv / conda
- 解释器版本
- 源码暴露
- 部署打包

### 1.2 核心分工

| 层级 | 责任 | 实现语言 |
|---|---|---|
| 算法流程 | AI 生成与人类审查 | StaticPy (Python 语法子集) |
| 高性能算子 | 运行时提供，AI 直接调用 | C/C++ (helper .so) |
| 编译与部署 | AOT 编译为 ELF | Chez Scheme + C launcher |
| 硬件接口 | CUDA / cuDNN / cuBLAS | NVIDIA 生态 |

### 1.3 为什么 AI 更适合用 StaticPy

- **语法子集小**：AI 生成代码时错误空间小。
- **类型强制**：函数签名明确，减少歧义。
- **依赖显式**：只有 `extern fn ... from "xxx_std"` 和系统 `.so`。
- **结果可执行**：编译通过即得到 ELF，行为确定。
- **无隐性上下文**：没有 Python 版本、pip、venv、PATH 等黑箱。

---

## 二、核心设计原则

### 2.1 AI 写算法，C++ 保性能，编译器保部署

StaticPy 本身不实现高性能算子。张量运算、CUDA kernel、PPO、特征工程全部下沉到 C/C++ helper。

StaticPy 只负责：
- 表达算法流程
- 调用 helper API
- 控制训练/推理循环
- 编译成 ELF

### 2.2 运行时加载依赖，不 pip 安装

StaticPy ELF 运行时依赖两类东西：
1. 系统库：`libc.so.6`, `libm.so.6`, `libdl.so.2`, `libpthread.so.0`
2. 显式 helper：如 `libtorch_std_helper.so`, `libonnx_helper.so`

没有 pip。没有 venv。没有 Python 解释器。

### 2.3 子集优先于超集

StaticPy 不支持：
- 类继承、多态
- 异常处理
- 生成器
- lambda / 闭包自由变量
- eval / exec
- 动态 getattr / setattr

支持：
- `if / while / for / def / return`
- `import`（映射到 prelude 模块）
- `extern fn`（声明 C helper）
- 类型标注
- 基础数组和字典操作

子集越小，AI 生成代码越可靠。

### 2.4 值类型与 C 连续内存

| StaticPy 类型 | 运行时实现 | 对应 C 类型 | 位置 |
|---|---|---|---|
| `int` | Chez fixnum | `int64_t` | 寄存器/栈 |
| `float` | Chez flonum | `double` | 寄存器/栈 |
| `bool` | Chez boolean | `bool` | 寄存器/栈 |
| `str` | Scheme string | `char*` | GC 堆 |
| `list[float]` | tagged-array | `double*` | C 堆，GC 回收 |
| `list[int]` | tagged-array | `int64_t*` | C 堆，GC 回收 |
| `dict` | hashtable | - | GC 堆 |
| `ptr` | C pointer | `void*` | C 堆 |

`list[float]` 和 `list[int]` 底层是 tagged-array：`#(data-ptr len)`。
- `data-ptr`：指向 C 连续内存
- `len`：数组长度
- GC guardian 自动回收 C 内存

---

## 三、核心文件职责

### 3.1 编译器与前端

| 文件 | 职责 |
|---|---|
| `static_translate.py` | Python → Scheme 翻译器、类型检查、import 映射 |
| `staticc.py` | .sp 子集编译器（自举链第三环） |
| `static_build.sh` | 一键编译：翻译 → AOT → 链接 ELF |

### 3.2 运行时与标准库

| 文件 | 职责 |
|---|---|
| `static_prelude.scm` | 值类型运行时：数组、字典、文件 IO、字符串、随机数、OS 接口 |
| `static_stdlib.scm` | 高级标准库：BLAS、LAPACK、libTorch FFI 封装、数组工具 |

### 3.3 C/C++ Helper（以 libTorch 为例）

| 文件 | 职责 |
|---|---|
| `libtorch_std_helper.h` | C API 头文件 |
| `libtorch_std_helper.cpp` | libTorch 桥接实现：张量创建、op、autograd、optimizer、JIT、PPO |
| `libtorch_std_helper.so` | 编译产物，ELF 运行时 `load-shared-object` 加载 |
| `build_torch_std_helper.sh` | helper 编译脚本 |

### 3.4 项目源码（以量化训练为例）

| 文件 | 职责 |
|---|---|
| `stock/stock_rl_train.static.py` | StaticPy 训练 ELF 源码 |
| `stock/export_rl_policy.py` | Python 导出 TorchScript policy/value 模型 |
| `stock/train_rl.py` | Python 参考实现，保留为算法来源 |

### 3.5 构建产物

| 文件 | 说明 |
|---|---|
| `stock_rl_train` | 独立 ELF 训练二进制 |
| `stock_rl_train.so` | Chez AOT 编译产物 |
| `stock/weights/rl_policy_latest.pt` | 最新 policy 模型，提交 GitHub |
| `stock/weights/rl_value_latest.pt` | 最新 value 模型，提交 GitHub |
| `stock/weights/rl_*_trained_YYYYMMDD_HHMMSS.pt` | 历史检查点，`.gitignore` 忽略 |

---

## 四、打包 ELF 流水线

完整流程见下图：

```
Python 源码 (.static.py)
    │
    ▼
[static_translate.py]
    │  1. 读取源码
    │  2. 提取 extern fn 声明
    │  3. AST 解析
    │  4. import / 模块别名解析
    │  5. dataclass / enum 收集
    │  6. 静态类型检查
    │  7. 生成 Scheme S-表达式（含 extern FFI 声明）
    ▼
${STEM}_code.ss
    │
    ▼
[static_build.sh]
    │  1. 合并 static_prelude.scm + static_stdlib.scm + user code
    │  2. Chez compile-file AOT 编译 → .so
    │  3. objcopy 嵌入 Chez boot 文件 → .o
    │  4. 写 C launcher
    │  5. gcc 链接 → ELF
    ▼
./${STEM}            # 独立 ELF 二进制
./${STEM}.so         # Chez AOT 编译产物
```

最终产物**不依赖 Python 解释器、pip 或 venv**，只需系统 libc/libm 和代码显式加载的 `.so`（如 `libtorch_std_helper.so`）。

### 4.1 一键构建

```bash
cd /opt/ReScheme
bash static_build.sh stock/stock_rl_train.static.py stock_rl_train
```

等价于手动执行：

```bash
# 1. 翻译
python3 static_translate.py stock/stock_rl_train.static.py > stock_rl_train_code.ss

# 2. 合并 prelude + stdlib + user code
cat static_prelude.scm static_stdlib.scm stock_rl_train_code.ss > merged.ss

# 3. AOT 编译
scheme --quiet compile.ss
# compile.ss 内容：
# (import (chezscheme))
# (compile-file "merged.ss")
# 输出 merged.sso，重命名为 stock_rl_train.so

# 4. 嵌入 Chez boot 文件
objcopy --input-target binary --output-target elf64-x86-64 petite.boot petite_boot.o
objcopy --input-target binary --output-target elf64-x86-64 scheme.boot scheme_boot.o

# 5. 写 C launcher
# 初始化 Chez heap，加载 boot 文件，调用 Sscheme_program("stock_rl_train.so", argc, argv)

# 6. gcc 链接
gcc launcher.c petite_boot.o scheme_boot.o \
    -I$CHEZ_DIR/boot/ta6le -L$CHEZ_DIR/boot/ta6le \
    -l:libkernel.a $CHEZ_DIR/lz4/lib/liblz4.a $CHEZ_DIR/zlib/libz.a \
    -ldl -lpthread -lm -ltinfo \
    -o stock_rl_train
```

### 4.2 产物

| 文件 | 说明 |
|---|---|
| `${STEM}` | 独立 ELF 可执行文件 |
| `${STEM}.so` | Chez AOT 编译的 Scheme 共享对象 |

运行时 ELF 会找到同目录下的 `.so` 加载。

### 4.3 运行

```bash
# 产物
./stock_rl_train                 # ELF 二进制
./stock_rl_train.so              # Chez AOT .so

# 运行（需要让动态链接器找到 libtorch 等 .so）
LD_LIBRARY_PATH=/data/venv/lib/python3.12/site-packages/torch/lib:$LD_LIBRARY_PATH \
  ./stock_rl_train 10000 60 1
```

### 4.4 部署形态

部署时只需要：
- ELF 二进制
- 显式 helper `.so`（如 `libtorch_std_helper.so`）
- 被调用的第三方 `.so`（如 `libtorch.so`, `libc10.so`）
- 数据文件和模型文件

最简部署示例：

```bash
cp myapp myapp.so target_dir/
# 若用到 libtorch_std_helper.so：
cp /opt/ReScheme/libtorch_std_helper.so target_dir/
cd target_dir
LD_LIBRARY_PATH=. ./myapp
```

不需要 Python、pip、venv、源代码。

---

## 五、运行时加载外部 .so

### 5.1 声明外部 C 函数

```python
extern fn torch_std_jit_load(path: str) -> ptr from "torch_std"
extern fn torch_std_ppo_update(policy: ptr, value: ptr,
                               states: ptr, n_states: int, state_dim: int,
                               actions: ptr, rewards: ptr,
                               lr: float, ppo_epochs: int, batch_size: int,
                               gamma: float, lam: float, clip_eps: float,
                               entropy_coef: float, value_coef: float) -> int from "stock_rl"
```

- `extern fn`：声明一个 C ABI 函数
- `from "torch_std"` / `from "stock_rl"`：表示该函数来自 `libtorch_std_helper.so` / `libstock_rl_helper.so`
- StaticPy 运行时会自动 `load-shared-object`

### 5.2 helper 命名约定

| helper 库 | `from` 名 | 实际 .so 文件名 |
|---|---|---|
| libTorch 桥接 | `"torch_std"` | `libtorch_std_helper.so` |
| 量化/RL 专用 | `"stock_rl"` | `libstock_rl_helper.so` |
| 自定义 helper | `"my_helper"` | `libmy_helper.so` |

约定：`lib<name>_helper.so` 对应 `from "<name>"`。

### 5.3 helper 加载位置

`static_stdlib.scm` 启动时会尝试：

```scheme
(load-shared-object "libtorch_std_helper.so")
(load-shared-object "libstock_rl_helper.so")
```

运行时动态链接器会按标准规则搜索：
1. `LD_LIBRARY_PATH`
2. `/etc/ld.so.conf`
3. 系统默认路径

建议把 helper `.so` 和 ELF 放在同一目录，或设置 `LD_LIBRARY_PATH`。

---

## 六、支持的 Python 子集

### 6.1 完全支持的语法

```python
# 变量与类型
x: int = 10
y: float = 3.14
name: str = "hello"
ok: bool = True

# 函数
def add(a: int, b: int) -> int:
    return a + b

# 控制流
def classify(x: int) -> str:
    if x > 0:
        return "positive"
    elif x < 0:
        return "negative"
    return "zero"

# 循环
def sum_arr(arr: list[float]) -> float:
    s: float = 0.0
    i: int = 0
    n: int = list_length(arr)
    while i < n:
        s = s + float_array_ref(arr, i)
        i = i + 1
    return s

# import 映射到 prelude
import random
import os

# 外部 C 函数声明
extern fn my_op(a: ptr, b: ptr) -> ptr from "my_helper"
```

### 6.2 有限支持

| 特性 | 说明 |
|---|---|
| 列表推导式 | 基于 `range`/`list` 的简化实现 |
| 元组解构 | `x, y = 1, 2` 支持 |
| 切片 | `a[1:3]`, `a[:j]`, `a[i:]` 支持 |
| dataclass | 支持，编译为 record |

### 6.3 不支持

- class / 继承 / 多态
- try / except / raise
- lambda / 闭包自由变量
- 生成器 / yield
- eval / exec
- 动态 getattr / setattr

---

## 七、类型系统

### 7.1 基本类型

| StaticPy 类型 | 说明 |
|---|---|
| `int` | 64 位有符号整数，fixnum |
| `float` | 双精度浮点数 |
| `bool` | 布尔值 |
| `str` | 字符串 |
| `list[T]` | 运行时长度数组，T 为 float/int |
| `array[T, N]` | 编译期定长数组 |
| `dict` | 字典（hashtable） |
| `ptr` | C 指针 |
| `tuple` | 元组（Scheme vector） |

### 7.2 类型标注规则

- 建议所有变量、参数、返回值都有类型标注。
- 未标注变量推断为 `Any`。
- `Any` 可赋值给任何类型，但 strict 模式会警告/报错。

```python
# 推荐
def train_step(states: ptr, actions: ptr, n: int) -> int:
    rc: int = torch_std_ppo_update(...)
    return rc

# 也支持（渐进式迁移）
def legacy(x):
    return x + 1
```

### 7.3 编译模式

| 模式 | 命令 | 行为 |
|---|---|---|
| strict（默认） | `python3 static_translate.py file.py` | 类型错误退出 |
| warn | `STATICPY_WARN=1 python3 static_translate.py file.py` | 类型错误作为警告，继续编译 |

---

## 八、AI 项目模板

### 8.1 最小项目结构

一个最小 StaticPy ML 项目结构：

```
my_staticpy_project/
├── src/
│   └── main.static.py          # StaticPy 算法流程
├── helper/
│   ├── libmyhelper.cpp         # C++ helper 实现
│   └── libmyhelper.h           # C API 头文件
├── build.sh                    # 构建脚本
├── README.md                   # AI 可读的 API 说明
└── .gitignore
```

### 8.2 main.static.py 模板

```python
# my_staticpy_project/src/main.static.py

extern fn my_helper_load_model(path: str) -> ptr from "my_helper"
extern fn my_helper_forward(model: ptr, input: ptr) -> ptr from "my_helper"
extern fn my_helper_train_step(model: ptr, data: ptr) -> int from "my_helper"

def main():
    model: ptr = my_helper_load_model("model.pt")
    if model == 0:
        print("failed to load model")
        return

    data: list[float] = make_float_array(100)
    # fill data ...

    rc: int = my_helper_train_step(model, torch_std_float_array_ptr(data))
    if rc != 0:
        print("train step failed")
        return

    print("ok")
```

### 8.3 build.sh 模板

```bash
#!/bin/bash
set -euo pipefail

# 1. 编译 C++ helper
g++ -O3 -shared -fPIC -std=c++17 helper/libmyhelper.cpp -o helper/libmy_helper.so

# 2. 编译 StaticPy ELF
bash /opt/ReScheme/static_build.sh src/main.static.py my_app

# 3. 运行
LD_LIBRARY_PATH=$PWD/helper:$LD_LIBRARY_PATH ./my_app
```

### 8.4 image/pipeline：官方最小可复用模板

`image/pipeline/` 是一个完整的最小项目模板：

```
image/pipeline/
├── main.py                    # 最小示例
├── build.sh                   # 项目级一键编译
├── torch_mlp.py               # 函数式 libTorch MLP
├── torch_cnn.py               # 函数式 libTorch CNN
├── torch_policy_gradient.py   # 函数式 REINFORCE
├── nn_lightning_mlp.py        # Lightning 风格 MLP
├── nn_lightning_cnn.py        # Lightning 风格 CNN
└── ... ELF/.so 产物
```

`build.sh` 内容：

```bash
#!/bin/bash
set -e
cd "$(dirname "$0")"
INPUT="${1:-main.py}"
STEM="${2:-main}"
python3 /opt/ReScheme/static_translate.py "$PWD/$INPUT" > "${STEM}_code.ss"
/opt/ReScheme/static_build.sh "$PWD/${STEM}_code.ss" "$STEM"
mv "/opt/ReScheme/$STEM" "./$STEM"
mv "/opt/ReScheme/$STEM.so" "./$STEM.so"
```

使用：

```bash
cd image/pipeline
./build.sh nn_lightning_mlp.py nn_lightning_mlp
LD_LIBRARY_PATH=/opt/ReScheme:/data/venv/lib/python3.12/site-packages/torch/lib ./nn_lightning_mlp
```

---

## 九、编写 C/C++ Helper

### 9.1 最小 helper 示例

`helper/libmyhelper.h`：

```cpp
#pragma once
#ifdef __cplusplus
extern "C" {
#endif

void* my_helper_create(int size);
void  my_helper_free(void* p);
int   my_helper_sum(void* p, int n);

#ifdef __cplusplus
}
#endif
```

`helper/libmyhelper.cpp`：

```cpp
#include "libmyhelper.h"
#include <cstdlib>

extern "C" {

void* my_helper_create(int size) {
    return malloc(size * sizeof(double));
}

void my_helper_free(void* p) {
    free(p);
}

int my_helper_sum(void* p, int n) {
    double* arr = static_cast<double*>(p);
    double s = 0.0;
    for (int i = 0; i < n; ++i) s += arr[i];
    return static_cast<int>(s);
}

}
```

### 9.2 StaticPy 声明

```python
extern fn my_helper_create(size: int) -> ptr from "my_helper"
extern fn my_helper_free(p: ptr) -> void from "my_helper"
extern fn my_helper_sum(p: ptr, n: int) -> int from "my_helper"
```

### 9.3 完整封装自定义 C 库流程

以封装一个自定义 C 库为例：

`mylib.c`：

```c
#include <math.h>
double mylib_sqrt(double x) { return sqrt(x); }
```

编译：

```bash
gcc -shared -fPIC -O3 mylib.c -o libmylib.so
```

`demo.py`：

```python
extern fn mylib_sqrt(x: float) -> float from "mylib"

def main():
    print(mylib_sqrt(2.0))
```

编译运行：

```bash
python3 /opt/ReScheme/static_translate.py demo.py > demo_code.ss
/opt/ReScheme/static_build.sh demo_code.ss demo
LD_LIBRARY_PATH=. ./demo
```

输出：

```
1.4142135623730951
```

### 9.4 helper 生态模式

每个领域一个 helper：

| helper | 领域 |
|---|---|
| `libtorch_std_helper.so` | 深度学习训练与推理 |
| `libonnx_helper.so` | ONNX Runtime 推理 |
| `libcv_helper.so` | 图像解码与预处理 |
| `libnlp_helper.so` | 分词与文本特征 |
| `libaudio_helper.so` | 音频特征与编解码 |

### 9.5 如果想做成公共运行时

1. 把 helper 源码放到独立仓库。
2. 提供 `build.sh` 编译 `.so`。
3. 提供 `README.md` 列出所有 `extern fn` 签名和类型。
4. StaticPy 项目通过 `LD_LIBRARY_PATH` 加载。

helper 不需要进入 StaticPy 核心仓库，可以独立演化。
---

## 十、最小示例

### 10.1 Hello World

```python
# hello.static.py
def main():
    print("hello staticpy")
```

```bash
bash static_build.sh hello.static.py hello
./hello
# 输出: hello staticpy
```

### 10.2 数组操作

```python
# array.static.py
def sum_floats(arr: list[float]) -> float:
    s: float = 0.0
    i: int = 0
    n: int = list_length(arr)
    while i < n:
        s = s + float_array_ref(arr, i)
        i = i + 1
    return s

def main():
    a: list[float] = make_float_array(3)
    float_array_set(a, 0, 1.0)
    float_array_set(a, 1, 2.0)
    float_array_set(a, 2, 3.0)
    print(sum_floats(a))
```

### 10.3 调用 libTorch helper

```python
# torch_minimal.static.py
extern fn torch_std_tensor_from_blob_3d(data: list[float], d0: int, d1: int, d2: int, dtype: int) -> ptr from "torch_std"
extern fn torch_std_jit_forward(module: ptr, input: ptr) -> ptr from "torch_std"
extern fn torch_std_jit_load(path: str) -> ptr from "torch_std"

def main():
    model: ptr = torch_std_jit_load("model.pt")
    if model == 0:
        print("load failed")
        return
    input_data: list[float] = make_float_array(7)
    # fill input_data ...
    input_t: ptr = torch_std_tensor_from_blob_3d(input_data, 1, 1, 7, 0)
    out: ptr = torch_std_jit_forward(model, input_t)
    print("forward ok")
```

---

## 十一、调试与错误

### 11.1 编译错误

```bash
python3 static_translate.py src/main.static.py
```

错误会显示行号和类型信息。

### 11.2 运行时错误

常见错误：

| 错误 | 原因 | 解决 |
|---|---|---|
| `no entry for "xxx"` | helper .so 未加载或函数未导出 | 检查 `LD_LIBRARY_PATH` 和 .so 编译 |
| `invalid memory reference` | C 指针越界或空指针 | 检查指针操作和数组边界 |
| `Exception in foreign-procedure` | C helper 抛异常 | 检查 helper 实现 |

### 11.3 调试建议

1. 先用 `static_translate.py` 单独检查翻译是否通过。
2. 用 `nm -D libxxx_helper.so` 检查符号是否导出。
3. 用 `LD_LIBRARY_PATH` 显式指定 helper 和第三方 .so 路径。
4. 在 StaticPy 代码里加 `print` 定位崩溃位置。

---

## 十二、一句话总结

> **StaticPy 让 AI Agent 用 Python 语法写算法，用 C/C++ helper 做性能，用编译器直接产出可部署的 ELF。无 Python 解释器、无 pip、无 venv——只有代码和可执行文件。**

---

## 延伸阅读

- [StaticPy 真实执行路径：从 Python 源码到 ELF 二进制](static_py_pipeline.md)
- [libtorch_std_helper 使用说明](libtorch_std_helper.md)
- [stock/stock_rl_train.static.py](../stock/stock_rl_train.static.py) — 量化训练 ELF 完整示例
