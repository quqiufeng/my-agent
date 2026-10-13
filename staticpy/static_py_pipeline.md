# StaticPy 真实执行路径：从 Python 源码到 ELF 二进制

> 本文档描述 StaticPy 工具链的完整流水线：Python 子集源码如何被翻译、如何集成运行时/外部 C 库、如何封装新的库、以及如何打包成独立 ELF 二进制。
> 
> 关键文件：
> - `static_translate.py` — Python → Scheme S-表达式翻译器 + 静态类型检查
> - `static_build.sh` — Scheme → Chez AOT `.so` → C launcher → ELF 二进制
> - `static_prelude.scm` — 值类型运行时（fixnum/flonum、数组、字典、GC）
> - `static_stdlib.scm` — 公共标准库封装（OpenBLAS、LAPACK、libTorch 等）
> - `build_torch_std_helper.sh` — libTorch C++ 桥接库编译脚本

---

## 一、总览

```
Python 源码 (.py)
    │
    ▼
[static_translate.py]
    │  1. 读取源码
    │  2. 提取 extern fn 声明
    │  3. AST 解析
    │  4. import / 模块别名解析
    │  5. dataclass / enum 收集
    │  6. 静态类型检查
    │  7. 生成 Scheme S-表达式 (含 extern FFI 声明)
    ▼
${STEM}_code.ss
    │
    ▼
[static_build.sh]
    │  1. 合并 prelude + stdlib + user code
    │  2. Chez compile-file AOT 编译 → .so
    │  3. objcopy 嵌入 Chez boot 文件 → .o
    │  4. 写 C launcher
    │  5. gcc 链接 → ELF
    ▼
./${STEM}            # 独立 ELF 二进制
./${STEM}.so         # Chez AOT 编译产物
```

最终产物**不依赖 Python 解释器、pip 或 venv**，只需系统 libc/libm 和代码显式加载的 `.so`（如 `libtorch_std_helper.so`）。

---

## 二、Phase 1：Python → Scheme 翻译

### 2.1 入口

```bash
python3 static_translate.py input.py > output.ss
```

`static_translate.py` 接收一个 Python 文件（或 stdin），输出 Scheme 代码到 stdout。

### 2.2 提取 `extern fn`

Python AST 不认识 `extern fn`，所以先通过正则提取：

```python
extern fn cblas_ddot(n: int, x: ptr, incx: int, y: ptr, incy: int) -> float from "openblas"

def main():
    print(cblas_ddot(...))
```

提取后：
- 这些行从源码中删除
- `EXTERN_FUNCTIONS["cblas_ddot"]` 记录参数、返回类型、库名
- 后续生成 Scheme `(foreign-procedure "cblas_ddot" (...) double)`

### 2.3 AST 解析与 import 处理

- `ast.parse(code)` 解析源码
- `parse_imports(tree)` 建立模块别名表：
  - `import numpy as np` → `MODULE_ALIASES["np"] = "numpy"`
  - `from np import array` → `IMPORTED_NAMES["array"] = "np"`
- import 语句本身不生成 Scheme 代码，只用于名字解析

### 2.4 静态类型检查

`typecheck_module(tree)` 做函数级类型检查：
- 收集函数签名与参数数量
- 构造 enum 常量环境
- 对每个 `FunctionDef` 递归检查
- 检查赋值、调用、下标、字段访问的类型一致性
- 未知类型被视为 `Any`，默认严格模式会报未定义名/参数数量错误

### 2.5 生成 Scheme

输出结构：

```scheme
;; extern FFI functions
(define cblas_ddot (foreign-procedure "cblas_ddot" (...) double))

;; Source: input.py

;; StaticPy functions
(define (static_add a b)
  (fx+ a b))

(define (static_main)
  (let ((x #f))
    (set! x (static_add 1 2))
    (print x)))

;; Entry point
(static_main)
```

翻译约定：
- 用户函数加 `static_` 前缀，避免与 Scheme 内置冲突
- Python 局部变量 → `let` + `set!`
- `int` 值类型 → Chez fixnum；`float` → flonum
- `list[float]` → C double 数组指针
- 类/dataclass → `define-record-type`
- enum → 顶层 `define Color_RED 0` 等

### 2.6 模块函数映射

`static_translate.py` 内置了常见 Python 模块到 Scheme 运行时函数的映射：

```python
import torch
import nn

def main():
    x = torch.randn(2, 3)      # → (torch-randn 2 3)
    model = nn.Sequential(...)  # → (nn-Sequential ...)
```

映射表在 `BUILTIN_MODULES` 中维护。新增映射只需加一行：

```python
"mylib": {
    "foo": "mylib-foo",
},
```

并在 `static_stdlib.scm` 中实现对应的 Scheme 函数。

---

## 三、Phase 2：运行时集成

### 3.1 两层运行时

编译时 `static_build.sh` 会把三段代码合并：

```
static_prelude.scm   ← 值类型运行时（必须）
static_stdlib.scm    ← 公共标准库封装（可选加载，失败时优雅跳过）
${STEM}_code.ss      ← 用户代码
```

**`static_prelude.scm`** 提供：
- fixnum/flonum 操作
- `make-float-array`、`float-array-set/ref`
- 字典 `make-dict`、`dict-get`、`dict-set!`
- Pythonic 通用列表 `py-list`
- 错误处理（Option/Result）
- GC guardian 自动释放 C 内存

**`static_stdlib.scm`** 提供公共 FFI 封装：
- OpenBLAS / LAPACK（CPU 矩阵运算）
- CUDA / cuBLAS / cuDNN（GPU）
- libcurl、libcjson、XGBoost、LightGBM、ONNX Runtime
- **libTorch 标准 API**（通过 `libtorch_std_helper.so`）

### 3.2 如何加载外部 .so

#### 方式 A：代码中写 `extern fn`（项目私有库）

```python
extern fn my_fun(x: int) -> float from "mylib"

def main():
    print(my_fun(42))
```

编译前把 `libmylib.so` 放到能找到的位置，运行时：

```bash
LD_LIBRARY_PATH=. ./myapp
```

#### 方式 B：扩展 `static_stdlib.scm`（公共库）

适合多项目复用的功能。例如封装 libTorch：

1. 在 `static_stdlib.scm` 中写：

```scheme
(define *mylib-available* #f)
(call-with-current-continuation
  (lambda (return)
    (with-exception-handler
      (lambda (e) (return))
      (lambda ()
        (load-shared-object "libmylib.so")
        (set! *mylib-available* #t)))))

(define mylib-foo #f)
(when *mylib-available*
  (set! mylib-foo (foreign-procedure "mylib_foo" (int) double)))

(define (mylib-foo-wrap x)
  (if *mylib-available*
    (mylib-foo x)
    (begin (display "mylib not available\n") 0.0)))
```

2. 在 `static_translate.py` 的 `BUILTIN_MODULES` 加映射：

```python
"mylib": {
    "foo": "mylib-foo-wrap",
},
```

3. 用户代码里直接调用：

```python
import mylib

def main():
    print(mylib.foo(42))
```

### 3.3 libTorch 集成示例

这是本项目最复杂的公共库封装，由三部分组成：

| 文件 | 职责 |
|------|------|
| `libtorch_std_helper.h` | C API 头文件 |
| `libtorch_std_helper.cpp` | libTorch C++ 标准 API 桥接实现 |
| `build_torch_std_helper.sh` | 编译 `.so` 的脚本 |
| `static_stdlib.scm` | Scheme 侧封装：tensor 创建、op、autograd、optimizer 等 |

编译 helper：

```bash
./build_torch_std_helper.sh
```

生成 `libtorch_std_helper.so` 后，`static_stdlib.scm` 会在加载时 `load-shared-object`。

---

## 四、Phase 3：Scheme → ELF 二进制

StaticPy ELF 打包流程已统一整理到 [《StaticPy 前端文档》](static_py_front.md#四打包-elf-流水线)。

该章节包含：
- 完整流水线图
- `static_build.sh` 内部步骤
- AOT 编译、objcopy、C launcher、gcc 链接细节
- 产物说明与部署示例
- `image/pipeline` 项目模板
- 自定义 C/C++ 库封装流程

以下只保留一句话总结：

> `static_build.sh` 合并 `static_prelude.scm` + `static_stdlib.scm` + 用户 Scheme 代码，通过 Chez `compile-file` AOT 编译为 `.so`，再用 C launcher 链接成独立 ELF 二进制。

---

## 五、image/pipeline：最小可复用模板

最小项目模板和 `build.sh` 用法已整理到 [《StaticPy 前端文档》](static_py_front.md#八ai-项目模板)。

---

## 六、如何给新项目封装自己的 C/C++ 库

自定义 C/C++ helper 的完整封装流程已整理到 [《StaticPy 前端文档》](static_py_front.md#九编写-cc-helper)。

---

## 七、缓存与增量编译

`static_build.sh` 用 md5 缓存：

```bash
PRELUDE_HASH=$(md5sum static_prelude.scm static_stdlib.scm static_translate.py code.ss | md5sum | cut -d' ' -f1)
```

如果输入和运行时没变，直接复用缓存的 `.so` 和 ELF。修改源码或 `static_stdlib.scm` 后缓存自动失效。

---

## 八、调试技巧

| 问题 | 方法 |
|------|------|
| 类型错误 | `python3 static_translate.py input.py` 直接看 stderr |
| Scheme 编译错误 | 查看 `/tmp/staticpy-cache/${STEM}_${HASH}.ss` |
| 运行时找不到 .so | `LD_LIBRARY_PATH=. ./app` |
| FFI 符号未找到 | 用 `nm -D libxxx.so \| grep symbol` 确认 |
| Chez 异常 | Scheme 源码加 `(trace ...)` 或分步 REPL 加载 |

---

## 九、一句话总结

> **StaticPy = Python 子集源码 → Scheme S-表达式 → Chez AOT .so → C launcher → 独立 ELF。**
> 
> 运行时集成靠 `static_stdlib.scm` 封装公共库，`extern fn` 接入项目私有库；最终产物无需 Python、pip 或 venv。
