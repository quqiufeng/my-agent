# staticpy — StaticPy 工具链（my-agent 独立版）

> 从 `/opt/ReScheme` 抽出的 **StaticPy 编译链**，在本目录**独立发展**（自定位路径，不再依赖 `/opt/ReScheme`）。
> 一句话：**用 Python 语法写代码 → 编译成单文件原生 ELF**（无 Python 运行时）。

## 原理（管线）
```
Python(.py)  --static_translate.py-->  Scheme(.ss)  --Chez AOT-->  .so  --objcopy+gcc-->  单文件 ELF
                    (渐进类型)                        (static_prelude.scm + static_stdlib.scm)
```

- 类型：`int/float/bool/list[T]` 等**值类型**（Chez fixnum/flonum，非 PyObject）。
- 性能：≈ 手写 Chez（fib(40) 仅慢 ~1.4%）。
- 支持 `extern fn ... from "prelude|openblas|..."` 走 FFI。

## 文件
| 文件 | 作用 |
|------|------|
| `static_translate.py` | 前端：Python 语法 → Scheme S-表达式（**构建期需 python3**） |
| `static_build.sh` | 驱动：翻译 → Chez AOT → 合并 boot → C launcher → ELF |
| `static_prelude.scm` / `static_stdlib.scm` | 运行时底座（GC/值类型/stdlib） |
| `static_prelude.c` | 预置 C 侧辅助 |
| `examples/` | `dot_product.static.py`、`matmul.static.py` |
| `tests/` + `test_staticpy.sh` | 端到端测试（basic/blas/closure/dataclass/fib/…） |
| `static_py_pipeline.md` / `static_py_front.md` | 设计文档 |

## 用法
```bash
cd /opt/my-agent/staticpy
bash static_build.sh examples/dot_product.static.py mytool   # 生成 ./mytool(ELF) + ./mytool.so
./mytool
bash test_staticpy.sh                                        # 跑全部用例
```

## 依赖（外部绝对路径，构建期）
| 组件 | 路径 | 说明 |
|------|------|------|
| Chez Scheme | `/opt/ChezScheme/ta6le`（可用 `CHEZ_SCHEME_DIR` 覆盖） | AOT 编译 + boot 文件 |
| torch 运行库 | `/data/venv/lib/python3.12/site-packages/torch/lib` | launcher 链接（`-lc10 -ltorch_cpu -ltorch`） |
| python3 | `/data/venv/bin/python3` | 仅**构建期**跑 `static_translate.py` |
| gcc / objcopy | 系统 | 链接与段处理 |

> 产物 ELF 依赖 `libm/libc/libtinfo` + torch 的 `.so`（rpath 已写）；**不含 Python 解释器**。

## 与 my-agent 的关系
- 本项目「运行时禁 Python」——StaticPy 可把**纯逻辑/数值工具**编译成原生 ELF 落地，合规。
- **限制**：不支持任意 PyPI 包（如 `aiohttp`/`paho-mqtt`/`deebot-client`/`ultralytics`）→
  这些（如科沃斯 `vacuum.py`）**无法**用 StaticPy 编译，仍需 Python。

## 开发/部署约定（本项目规则）
- **开发**：优先用 **Python + 标准库** 写（`os/sys/math/re/json` 等），保持干净、少依赖。
- **部署**：用 staticpy 编成**单文件 ELF** → 目标机**零 Python** 运行。
- **可编判定**：只用了 StaticPy 子集 + 已覆盖 stdlib 的 → 可编（如数值/逻辑/数据处理）。
- **不可编**：
  - 用了**第三方包**（`aiohttp`/`rapidocr`/`deebot-client`/`ultralytics`…）；
  - 用了**未覆盖的 stdlib**（`socket`/`http.server`/`threading` 等，如 `web/server.py`）；
  → 这类作为**独立 Python 工具**保留，部署环境需带 Python。
- **构建期**仍需 Python（`static_translate.py` 依赖 `ast`）——这是唯一无法回避的 Python 依赖。


## 相对原仓库的改动
- `static_build.sh`：`RESCHEME_DIR` 改为**脚本所在目录**（自定位）。
- `test_staticpy.sh`：`cd` 到**脚本所在目录**。

*来源：`/opt/ReScheme`（三环自举静态编译框架第 2 环）。*
