#!/usr/bin/env python3
"""StaticPy 翻译器 — Python 静态子集 → Scheme S-表达式
语法: Python + 类型标注 (int/float/bool/list[T])
语义: int/float = 值类型（Chez fixnum/flonum），非 PyObject*
"""
import sys
import re
import json
import ast
import keyword

# ====== Scheme 保留字/不可用作变量名的标识符 ======
SCHEME_RESERVED = {
    "if", "else", "then", "cond", "case", "let", "let*", "letrec", "letrec*",
    "lambda", "define", "set!", "begin", "and", "or", "not", "quote",
    "quasiquote", "unquote", "unquote-splicing", "do", "while", "until",
    "for", "when", "unless", "delay", "force", "call-with-current-continuation",
    "call/cc", "dynamic-wind", "values", "call-with-values", "eval", "apply",
    "map", "for-each", "exists", "fold-left", "fold-right", "filter", "assq",
    "assv", "assoc", "memq", "memv", "member", "null?", "pair?", "list?",
    "number?", "string?", "vector?", "boolean?", "procedure?", "symbol?",
    "eq?", "eqv?", "equal?", "char?", "integer?", "real?", "complex?",
}

def mangle_name(name):
    """把 Python 变量名转义为合法的 Scheme 标识符"""
    if name in SCHEME_RESERVED or keyword.iskeyword(name):
        return f"{name}_py"
    return name


def scheme_name(name):
    """把 Python 运行时辅助函数名映射为 Scheme 预置原语"""
    RUNTIME_MAP = {
        "py_list": "py-list",
        "py_list_append": "py-list-append",
        "py_list_ref": "py-list-ref",
        "py_list_length": "py-list-length",
        "list_to_py_list": "list->py-list",
        "dict_copy": "dict-copy",
    }
    return RUNTIME_MAP.get(name, name)

# ====== C 类型映射 ======
TYPE_MAP = {
    "int": "int",
    "float": "double",
    "double": "double",
    "bool": "boolean",
    "str": "string",
    "ptr": "void*",
}

# ====== StaticPy 类型系统 ======

class Type:
    """内部类型表示：base + 可选泛型参数"""
    __slots__ = ("base", "params")
    def __init__(self, base, params=None):
        self.base = base
        self.params = params or []

    def __repr__(self):
        if not self.params:
            return self.base
        return f"{self.base}[{','.join(str(p) for p in self.params)}]"

    def __eq__(self, other):
        if not isinstance(other, Type):
            return False
        return self.base == other.base and self.params == other.params

    def __hash__(self):
        return hash((self.base, tuple(str(p) for p in self.params)))


def parse_type(node):
    """把 Python ast 类型标注解析为 Type 对象"""
    if node is None:
        return None
    # AnnAssign / ast.arg 等节点上取 .annotation
    ann = getattr(node, 'annotation', node)
    if ann is None:
        return None
    if isinstance(ann, ast.Name):
        base = ann.id
        if base == "list":
            return Type("list", [Type("Any")])
        if base == "tuple":
            return Type("tuple", [Type("Any")])
        return Type(base)
    if isinstance(ann, ast.Constant) and isinstance(ann.value, str):
        return Type(ann.value)
    if isinstance(ann, ast.Subscript):
        if isinstance(ann.value, ast.Name):
            base = ann.value.id
            params = []
            if base == "Callable" and isinstance(ann.slice, ast.Tuple) and len(ann.slice.elts) == 2:
                # Callable[[arg1, ...], ret]：第一个元素是参数列表
                args_node = ann.slice.elts[0]
                ret_node = ann.slice.elts[1]
                if isinstance(args_node, ast.List):
                    for elt in args_node.elts:
                        t = parse_type(elt)
                        if t:
                            params.append(t)
                t = parse_type(ret_node)
                if t:
                    params.append(t)
                return Type(base, params)
            # 统一处理单参数和多参数泛型
            if isinstance(ann.slice, ast.Tuple):
                for elt in ann.slice.elts:
                    t = parse_type(elt)
                    if t:
                        params.append(t)
            else:
                t = parse_type(ann.slice)
                if t:
                    params.append(t)
            return Type(base, params)
    if isinstance(ann, ast.BinOp):
        # 暂不支持的复杂类型表达式
        return None
    return None


def type_from_str(s):
    """从字符串解析类型（用于兼容旧的 TYPE_ENV 字符串）"""
    if s is None:
        return None
    if isinstance(s, Type):
        return s
    # 解析泛型：list[float], result[float,str], array[int,5]
    s = s.strip()
    if "[" in s and s.endswith("]"):
        base, rest = s.split("[", 1)
        rest = rest[:-1]
        params = [type_from_str(p.strip()) for p in rest.split(",")]
        return Type(base, [p for p in params if p])
    return Type(s)


def type_to_str(t):
    return str(t) if t else "<unknown>"


# 类型兼容性：t1 能否赋值给 t2
def is_subtype(t1, t2):
    if t1 is None or t2 is None:
        return True  # 未知类型不报错
    if not isinstance(t1, Type):
        t1 = type_from_str(t1)
    if not isinstance(t2, Type):
        t2 = type_from_str(t2)
    # Any 类型：任何类型都可赋值给 Any，Any 可赋值给任何类型
    if t1.base == "Any" or t2.base == "Any":
        return True
    if t1 == t2:
        return True
    # int 可隐式提升为 float
    if t1.base == "int" and t2.base == "float":
        return True
    # result/option 联合类型：ok[T] <: result[T, E], error[E] <: result[T, E]
    if t2.base == "result" and len(t2.params) == 2:
        if t1.base == "ok" and len(t1.params) == 1:
            return is_subtype(t1.params[0], t2.params[0])
        if t1.base == "error" and len(t1.params) == 1:
            return is_subtype(t1.params[0], t2.params[1])
        if t1.base == "result" and len(t1.params) == 2:
            return is_subtype(t1.params[0], t2.params[0]) and is_subtype(t1.params[1], t2.params[1])
    # some[T] <: option[T], none <: option[T]
    if t2.base == "option" and len(t2.params) == 1:
        if t1.base == "some" and len(t1.params) == 1:
            return is_subtype(t1.params[0], t2.params[0])
        if t1.base == "none":
            return True
        if t1.base == "option" and len(t1.params) == 1:
            return is_subtype(t1.params[0], t2.params[0])
    # 泛型参数数量一致时逐参数协变（简化）
    if t1.base == t2.base and len(t1.params) == len(t2.params):
        return all(is_subtype(a, b) for a, b in zip(t1.params, t2.params))
    # arrow 类型与 Callable 兼容（都用于函数值）
    if t1.base == "arrow" and t2.base in ("Callable", "arrow"):
        if len(t1.params) == len(t2.params):
            # 函数类型参数：参数逆变、返回值协变（这里简化为逐参数协变，因为都是 int）
            return all(is_subtype(a, b) for a, b in zip(t1.params, t2.params))
        return False
    if t2.base == "Any":
        return True
    # tuple[...] 与裸 tuple/Tuple 兼容
    if t1.base == "tuple" and t2.base in ("tuple", "Tuple"):
        return True
    # list[...] 与裸 list 兼容
    if t1.base == "list" and t2.base == "list":
        return True
    # array[...] 与裸 array 兼容
    if t1.base == "array" and t2.base == "array":
        return True
    return False


def is_fully_typed(t):
    """检查类型是否不含 Any"""
    if t is None:
        return False
    if not isinstance(t, Type):
        t = type_from_str(t)
    if t.base == "Any":
        return False
    return all(is_fully_typed(p) for p in t.params)


# 内置函数/运算符统一类型规则表
# 运算符规则：{op_class_name: (allowed_operand_bases_or_special, result_type)}
# 其中 result_type 可以是 Type、字符串，或 (lambda lt rt: Type(...)) 函数
BUILTIN_BINOP_RULES = {
    "Add": (None, lambda lt, rt: _binop_result(lt, rt, "+")),
    "Sub": (None, lambda lt, rt: _binop_result(lt, rt, "-")),
    "Mult": (None, lambda lt, rt: _binop_result(lt, rt, "*")),
    "Div": (None, lambda lt, rt: _binop_result(lt, rt, "/")),
    "FloorDiv": (None, lambda lt, rt: _binop_result(lt, rt, "//")),
    "Mod": (None, lambda lt, rt: _binop_result(lt, rt, "%")),
    "Pow": (None, lambda lt, rt: _binop_result(lt, rt, "**")),
    "BitOr": ("int", lambda lt, rt: Type("int")),
    "BitXor": ("int", lambda lt, rt: Type("int")),
    "BitAnd": ("int", lambda lt, rt: Type("int")),
    "LShift": ("int", lambda lt, rt: Type("int")),
    "RShift": ("int", lambda lt, rt: Type("int")),
}

def _binop_result(lt, rt, op_name):
    """根据左右操作数类型推断二元运算结果类型"""
    if lt.base in ("int", "float") and rt.base in ("int", "float"):
        if lt.base == "float" or rt.base == "float" or op_name == "/":
            return Type("float")
        return Type("int")
    if lt.base == "str" and rt.base == "str" and op_name == "+":
        return Type("str")
    if lt.base == "list" and rt.base == "list" and op_name == "+":
        # 列表拼接：元素类型取公共类型
        if lt.params and rt.params:
            return Type("list", [common_supertype(lt.params[0], rt.params[0]) or Type("?")])
        return Type("list", [Type("?")])
    return None

def common_supertype(t1, t2):
    """返回两个类型的最小公共超类型"""
    if t1 is None or t2 is None:
        return None
    if not isinstance(t1, Type):
        t1 = type_from_str(t1)
    if not isinstance(t2, Type):
        t2 = type_from_str(t2)
    if is_subtype(t1, t2):
        return t2
    if is_subtype(t2, t1):
        return t1
    if t1.base in ("int", "float") and t2.base in ("int", "float"):
        return Type("float")
    if t1.base == t2.base and t1.base == "list":
        p = common_supertype(t1.params[0], t2.params[0]) if t1.params and t2.params else None
        return Type("list", [p] if p else [])
    return Type("Any")


def common_numeric_type(t1, t2):
    """返回两个数值类型的公共类型"""
    result = common_supertype(t1, t2)
    if result and result.base in ("int", "float"):
        return result
    return None


# 函数签名注册表：函数名 -> ([arg_type, ...], return_type)
FUNCTION_SIGS = {}

# 内置函数/模块函数统一返回类型表（fname/scheme_fn -> Type）
# 查找顺序：先 BUILTIN_FN_RETURN_TYPES，再 MODULE_FN_RETURN_TYPES
BUILTIN_FN_RETURN_TYPES = {
    "len": Type("int"),
    "int": Type("int"),
    "float": Type("float"),
    "bool": Type("bool"),
    "str": Type("str"),
    "abs": Type("float"),
    "pow": Type("float"),
    "range": Type("list", [Type("int")]),
    "print": Type("none"),
    "exit": Type("none"),
    "make_float_array": Type("list", [Type("float")]),
    "make_int_array": Type("list", [Type("int")]),
}

MODULE_FN_RETURN_TYPES = {
    # np
    "np-array": Type("list", [Type("float")]),
    "np-zeros": Type("list", [Type("float")]),
    "np-ones": Type("list", [Type("float")]),
    "np-dot": Type("float"),
    "np-daxpy": Type("list", [Type("float")]),
    "np-copy": Type("list", [Type("float")]),
    "np-scal": Type("list", [Type("float")]),
    "np-gemv": Type("list", [Type("float")]),
    "np-gemm": Type("list", [Type("float")]),
    "np-sum": Type("float"),
    "np-mean": Type("float"),
    "np-max": Type("float"),
    "np-min": Type("float"),
    "np-sqrt": Type("float"),
    "np-exp": Type("float"),
    "np-abs": Type("float"),
    "np-argmax": Type("int"),
    "np-arange": Type("list", [Type("int")]),
    "np-linspace": Type("list", [Type("float")]),
    "np-concatenate": Type("list", [Type("float")]),
    "np-clip": Type("list", [Type("float")]),
    # torch
    "torch-tensor": Type("torch-tensor"),
    "torch-tensor-int64": Type("torch-tensor"),
    "torch-empty": Type("torch-tensor"),
    "torch-zeros": Type("torch-tensor"),
    "torch-ones": Type("torch-tensor"),
    "torch-add": Type("torch-tensor"),
    "torch-mul": Type("torch-tensor"),
    "torch-sub": Type("torch-tensor"),
    "torch-matmul": Type("torch-tensor"),
    "torch-clone": Type("torch-tensor"),
    "torch-reshape": Type("torch-tensor"),
    "torch-to-list": Type("list", [Type("float")]),
    "torch-available": Type("bool"),
    "torch-conv2d": Type("torch-tensor"),
        "torch-randn": Type("torch-tensor"),
        "torch-randint": Type("torch-tensor"),
    "torch-relu": Type("torch-tensor"),
    "torch-sigmoid": Type("torch-tensor"),
    "torch-tanh": Type("torch-tensor"),
    "torch-linear": Type("torch-tensor"),
    "torch-mse-loss": Type("torch-tensor"),
    "torch-cross-entropy": Type("torch-tensor"),
    "torch-backward": Type("bool"),
    "torch-zero-grad": Type("bool"),
    "torch-set-requires-grad": Type("bool"),
    "torch-adam": Type("ptr"),
    "torch-optimizer-step": Type("bool"),
    "torch-optimizer-zero-grad": Type("bool"),
    "torch-manual-seed": Type("bool"),
    "torch-sd-unet-forward": Type("torch-tensor"),
    "torch-load-image": Type("torch-tensor"),
    "torch-save-image": Type("void"),
    "torch-ddpm-betas": Type("torch-tensor"),
    "torch-ddpm-add-noise": Type("torch-tensor"),
    "torch-jit-load": Type("ptr"),
    "torch-jit-forward": Type("torch-tensor"),
    "torch-jit-delete": Type("void"),
    "torch-save-state-dict": Type("int"),
    "torch-safetensors-load": Type("ptr"),
    "torch-safetensors-count": Type("int"),
    "torch-safetensors-name": Type("string"),
    "torch-safetensors-tensor": Type("torch-tensor"),
    "torch-safetensors-free": Type("void"),
    "torch-safetensors-get-tensor-by-name": Type("torch-tensor"),
    "torch-lora-apply": Type("torch-tensor"),
    "torch-lora-merge-into": Type("int"),
    "torch-sample-ddim": Type("torch-tensor"),
    "torch-sample-euler": Type("torch-tensor"),
    "torch-sample-euler-ancestral": Type("torch-tensor"),
    "torch-sample-dpmpp-2m": Type("torch-tensor"),
    "torch-sampler-sigmas": Type("torch-tensor"),
    "torch-image-resize": Type("torch-tensor"),
    "torch-image-crop": Type("torch-tensor"),
    "torch-image-composite": Type("torch-tensor"),
    "torch-color-convert": Type("torch-tensor"),
    "torch-controlnet-forward": Type("torch-tensor"),
    "torch-controlnet-apply": Type("torch-tensor"),
    "torch-vae-encode-tiled": Type("torch-tensor"),
        "torch-vae-decode-tiled": Type("torch-tensor"),
        "torch-clip-tokenizer-create": Type("ptr"),
        "torch-clip-tokenizer-encode": Type("torch-tensor"),
        "torch-clip-tokenizer-free": Type("void"),
        "torch-clip-text-forward": Type("torch-tensor"),
        "torch-gguf-load": Type("ptr"),
        "torch-gguf-tensor-count": Type("int"),
        "torch-gguf-tensor-name": Type("string"),
        "torch-gguf-load-tensor": Type("torch-tensor"),
        "torch-gguf-load-tensor-by-name": Type("torch-tensor"),
        "torch-gguf-free": Type("void"),
        "torch-sdxl-unet-forward": Type("torch-tensor"),
        "torch-sdxl-dual-clip": Type("torch-tensor"),
        "torch-t5-tokenizer-create": Type("ptr"),
        "torch-t5-tokenizer-encode": Type("torch-tensor"),
        "torch-t5-tokenizer-free": Type("void"),
        "torch-flux-forward": Type("torch-tensor"),
        "torch-fm-sigmas": Type("torch-tensor"),
        "torch-fm-step": Type("torch-tensor"),
    "torch-conv2d": Type("torch-tensor"),
    "torch-max-pool2d": Type("torch-tensor"),
    "torch-avg-pool2d": Type("torch-tensor"),
    "torch-softmax": Type("torch-tensor"),
    "torch-log-softmax": Type("torch-tensor"),
    "torch-sum": Type("torch-tensor"),
    "torch-mean": Type("torch-tensor"),
    "torch-argmax": Type("int"),
    "torch-multinomial": Type("torch-tensor"),
    "torch-cat": Type("torch-tensor"),
    "torch-stack": Type("torch-tensor"),
    "torch-gather": Type("torch-tensor"),
    "torch-index-select": Type("torch-tensor"),
    "torch-squeeze": Type("torch-tensor"),
    "torch-unsqueeze": Type("torch-tensor"),
    "torch-transpose": Type("torch-tensor"),
    "nn-linear": Type("Any"),
    "nn-conv2d": Type("Any"),
    "nn-flatten": Type("Any"),
    "nn-batch-norm1d": Type("Any"),
    "nn-batch-norm2d": Type("Any"),
    "nn-Sequential": Type("Any"),
    "nn-relu": Type("Any"),
    "nn-sigmoid": Type("Any"),
    "nn-tanh": Type("Any"),
    "nn-parameters": Type("Any"),
    "nn-call": Type("torch-tensor"),
    "torch-div": Type("torch-tensor"),
    "torch-pow": Type("torch-tensor"),
    "torch-exp": Type("torch-tensor"),
    "torch-log": Type("torch-tensor"),
    "torch-sqrt": Type("torch-tensor"),
    "torch-neg": Type("torch-tensor"),
    "torch-abs": Type("torch-tensor"),
    "torch-clamp": Type("torch-tensor"),
    "torch-sum-dim": Type("torch-tensor"),
    "torch-mean-dim": Type("torch-tensor"),
    "torch-max-dim": Type("torch-tensor"),
    "torch-min-dim": Type("torch-tensor"),
    "torch-argmax-dim": Type("torch-tensor"),
    "torch-l1-loss": Type("torch-tensor"),
    "torch-bce-loss": Type("torch-tensor"),
    "torch-bce-with-logits-loss": Type("torch-tensor"),
    "torch-nll-loss": Type("torch-tensor"),
    "torch-batch-norm1d": Type("torch-tensor"),
    "torch-batch-norm2d": Type("torch-tensor"),
    "torch-adamw": Type("ptr"),
    "torch-sgd": Type("ptr"),
    "torch-clip-grad-norm": Type("bool"),
    "torch-cuda-is-available": Type("bool"),
    "torch-to-cuda": Type("torch-tensor"),
    "torch-to-cpu": Type("torch-tensor"),
    "torch-is-cuda": Type("bool"),
    "torch-where": Type("torch-tensor"),
    "torch-eq": Type("torch-tensor"),
    "torch-gt": Type("torch-tensor"),
    "torch-lt": Type("torch-tensor"),
    "torch-ge": Type("torch-tensor"),
    "torch-le": Type("torch-tensor"),
    "torch-detach": Type("torch-tensor"),
    "torch-to-dtype": Type("torch-tensor"),
    "torch-numel": Type("int"),
    "torch-grad": Type("torch-tensor"),
    "torch-has-grad": Type("bool"),
    # math
    "sin": Type("float"), "cos": Type("float"), "tan": Type("float"),
    "log": Type("float"), "log2": Type("float"), "log10": Type("float"), "exp": Type("float"),
    "sqrt": Type("float"), "abs": Type("float"), "pow": Type("float"), "fmod": Type("float"),
    "floor": Type("float"), "ceil": Type("float"), "round": Type("float"),
    "sinh": Type("float"), "cosh": Type("float"), "tanh": Type("float"),
    "atan2": Type("float"), "asin": Type("float"), "acos": Type("float"), "atan": Type("float"),
    "pi": Type("float"), "e": Type("float"),
    # random
    "random_seed": Type("none"),
    "random_float": Type("float"),
    "random_randint": Type("int"),
    "random_uniform": Type("float"),
    "random_choice": Type("?"),
    # json
    "parse_json": Type("dict"),
    "json_dumps": Type("str"),
    # time
    "clock": Type("float"),
    "sleep": Type("none"),
    "format_time": Type("str"),
    # os
    "os_list_dir": Type("list", [Type("str")]),
    "os_mkdir": Type("none"),
    "os_rmdir": Type("none"),
    "os_getenv": Type("str"),
    "os_cwd": Type("str"),
    "os_move_file": Type("none"),
    "os_delete_file": Type("none"),
    "os_shell": Type("int"),
    "os_file_exists": Type("bool"),
    "os_file_size": Type("int"),
    # urllib
    "http_get_simple": Type("str"),
    # cuda / la
    "cuda-gemm": Type("list", [Type("float")]),
    "la-solve": Type("list", [Type("float")]),
    "la-svd": Type("list", [Type("float")]),
    "la-eigvals": Type("list", [Type("float")]),
}

# ====== 外部 FFI 函数注册表 ======
EXTERN_FUNCTIONS = {}

# ====== 模块别名/导入符号表 ======
# import numpy as np  → MODULE_ALIASES["np"] = "np" (resolved module name)
# from np import array → IMPORTED_NAMES["array"] = "np"
MODULE_ALIASES = {}
IMPORTED_NAMES = {}

# 记录已定义的 dataclass 类型名 -> 字段名 -> 字段类型
RECORD_TYPES = {}
RECORD_FIELDS = {}


# 内置模块及其函数映射（模块名 -> {函数名: Scheme 函数名})
BUILTIN_MODULES = {
    "np": {
        "array": "np-array",
        "dot": "np-dot",
        "daxpy": "np-daxpy",
        "copy": "np-copy",
        "scal": "np-scal",
        "gemv": "np-gemv",
        "gemm": "np-gemm",
        "matmul": "np-gemm",
        "sum": "np-sum",
        "mean": "np-mean",
        "max": "np-max",
        "min": "np-min",
        "zeros": "np-zeros",
        "ones": "np-ones",
        "sqrt": "np-sqrt",
        "exp": "np-exp",
        "abs": "np-abs",
        "argmax": "np-argmax",
        "arange": "np-arange",
        "linspace": "np-linspace",
        "concatenate": "np-concatenate",
        "clip": "np-clip",
    },
    "la": {
        "solve": "la-solve",
        "svd": "la-svd",
        "eigvals": "la-eigvals",
    },
    "torch": {
        "tensor": "torch-tensor",
        "tensor_int64": "torch-tensor-int64",
        "empty": "torch-empty",
        "zeros": "torch-zeros",
        "ones": "torch-ones",
        "randn": "torch-randn",
        "add": "torch-add",
        "mul": "torch-mul",
        "sub": "torch-sub",
        "matmul": "torch-matmul",
        "clone": "torch-clone",
        "from_raw": "torch-from-raw",
        "reshape": "torch-reshape",
        "relu": "torch-relu",
        "sigmoid": "torch-sigmoid",
        "tanh": "torch-tanh",
        "linear": "torch-linear",
        "mse_loss": "torch-mse-loss",
        "cross_entropy": "torch-cross-entropy",
        "backward": "torch-backward",
        "zero_grad": "torch-zero-grad",
        "set_requires_grad": "torch-set-requires-grad",
        "adam": "torch-adam",
        "optimizer_step": "torch-optimizer-step",
        "optimizer_zero_grad": "torch-optimizer-zero-grad",
        "manual_seed": "torch-manual-seed",
        "to_list": "torch-to-list",
        "available": "torch-available",
        "conv2d": "torch-conv2d",
        "max_pool2d": "torch-max-pool2d",
        "avg_pool2d": "torch-avg-pool2d",
        "softmax": "torch-softmax",
        "log_softmax": "torch-log-softmax",
        "sum": "torch-sum",
        "mean": "torch-mean",
        "argmax": "torch-argmax",
        "multinomial": "torch-multinomial",
        "cat": "torch-cat",
        "stack": "torch-stack",
        "gather": "torch-gather",
        "index_select": "torch-index-select",
        "squeeze": "torch-squeeze",
        "unsqueeze": "torch-unsqueeze",
        "transpose": "torch-transpose",
        "div": "torch-div",
        "pow": "torch-pow",
        "exp": "torch-exp",
        "log": "torch-log",
        "sqrt": "torch-sqrt",
        "neg": "torch-neg",
        "abs": "torch-abs",
        "clamp": "torch-clamp",
        "sum_dim": "torch-sum-dim",
        "mean_dim": "torch-mean-dim",
        "max_dim": "torch-max-dim",
        "min_dim": "torch-min-dim",
        "argmax_dim": "torch-argmax-dim",
        "l1_loss": "torch-l1-loss",
        "bce_loss": "torch-bce-loss",
        "bce_with_logits_loss": "torch-bce-with-logits-loss",
        "nll_loss": "torch-nll-loss",
        "batch_norm1d": "torch-batch-norm1d",
        "batch_norm2d": "torch-batch-norm2d",
        "adamw": "torch-adamw",
        "sgd": "torch-sgd",
        "clip_grad_norm": "torch-clip-grad-norm",
        "cuda_is_available": "torch-cuda-is-available",
        "to_cuda": "torch-to-cuda",
        "to_cpu": "torch-to-cpu",
        "is_cuda": "torch-is-cuda",
        "where": "torch-where",
        "eq": "torch-eq",
        "gt": "torch-gt",
        "lt": "torch-lt",
        "ge": "torch-ge",
        "le": "torch-le",
        "detach": "torch-detach",
        "to_dtype": "torch-to-dtype",
        "numel": "torch-numel",
        "grad": "torch-grad",
        "has_grad": "torch-has-grad",
        # SD UNet / JIT / DDPM / Image I/O extensions
        "sd_unet_forward": "torch-sd-unet-forward",
        "load_image": "torch-load-image",
        "save_image": "torch-save-image",
        "ddpm_betas": "torch-ddpm-betas",
        "ddpm_add_noise": "torch-ddpm-add-noise",
        "jit_load": "torch-jit-load",
        "jit_forward": "torch-jit-forward",
        "jit_delete": "torch-jit-delete",
        "save_state_dict": "torch-save-state-dict",
        # GGUF model loader
        "gguf_load": "torch-gguf-load",
        "gguf_tensor_count": "torch-gguf-tensor-count",
        "gguf_tensor_name": "torch-gguf-tensor-name",
        "gguf_load_tensor": "torch-gguf-load-tensor",
        "gguf_load_tensor_by_name": "torch-gguf-load-tensor-by-name",
        "gguf_free": "torch-gguf-free",
        # SDXL UNet
        "sdxl_unet_forward": "torch-sdxl-unet-forward",
        "sdxl_dual_clip": "torch-sdxl-dual-clip",
        # T5 tokenizer
        "t5_tokenizer_create": "torch-t5-tokenizer-create",
        "t5_tokenizer_encode": "torch-t5-tokenizer-encode",
        "t5_tokenizer_free": "torch-t5-tokenizer-free",
        # FLUX
        "flux_forward": "torch-flux-forward",
        # Flow Matching scheduler
        "fm_sigmas": "torch-fm-sigmas",
        "fm_step": "torch-fm-step",
        "randint": "torch-randint",
        # CLIP tokenizer
        "clip_tokenizer_create": "torch-clip-tokenizer-create",
        "clip_tokenizer_encode": "torch-clip-tokenizer-encode",
        "clip_tokenizer_free": "torch-clip-tokenizer-free",
        # CLIP text encoder
        "clip_text_forward": "torch-clip-text-forward",
        # safetensors
        "safetensors_load": "torch-safetensors-load",
        "safetensors_count": "torch-safetensors-count",
        "safetensors_name": "torch-safetensors-name",
        "safetensors_tensor": "torch-safetensors-tensor",
        "safetensors_free": "torch-safetensors-free",
        "safetensors_get_tensor_by_name": "torch-safetensors-get-tensor-by-name",
        # LoRA
        "lora_apply": "torch-lora-apply",
        "lora_merge_into": "torch-lora-merge-into",
        # Samplers
        "sample_ddim": "torch-sample-ddim",
        "sample_euler": "torch-sample-euler",
        "sample_euler_ancestral": "torch-sample-euler-ancestral",
        "sample_dpmpp_2m": "torch-sample-dpmpp-2m",
        "sampler_sigmas": "torch-sampler-sigmas",
        # Image processing
        "image_resize": "torch-image-resize", "image_resize_float": "torch-image-resize-float",
        "image_crop": "torch-image-crop",
        "image_composite": "torch-image-composite",
        "color_convert": "torch-color-convert",
        # ControlNet
        "controlnet_forward": "torch-controlnet-forward",
        "controlnet_apply": "torch-controlnet-apply",
        # VAE tiling
        "vae_encode_tiled": "torch-vae-encode-tiled",
        "vae_decode_tiled": "torch-vae-decode-tiled",
    },
    "nn": {
        "linear": "nn-linear",
        "conv2d": "nn-conv2d",
        "flatten": "nn-flatten",
        "batch_norm1d": "nn-batch-norm1d",
        "batch_norm2d": "nn-batch-norm2d",
        "Sequential": "nn-Sequential",
        "relu": "nn-relu",
        "sigmoid": "nn-sigmoid",
        "tanh": "nn-tanh",
        "parameters": "nn-parameters",
        "call": "nn-call",
    },
    "cuda": {
        "gemm": "cuda-gemm",
    },
    "math": {
        "sin": "sin", "cos": "cos", "tan": "tan",
        "log": "log", "log2": "log2", "log10": "log10", "exp": "exp",
        "sqrt": "sqrt", "abs": "abs", "pow": "pow", "fmod": "fmod",
        "floor": "floor", "ceil": "ceil", "round": "round",
        "sinh": "sinh", "cosh": "cosh", "tanh": "tanh",
        "atan2": "atan2", "asin": "asin", "acos": "acos", "atan": "atan",
        "pi": "pi", "e": "e",
    },
    "random": {
        "seed": "random_seed",
        "random": "random_float",
        "randint": "random_randint",
        "uniform": "random_uniform",
        "choice": "random_choice",
    },
    "json": {
        "loads": "parse_json",
        "dumps": "json_dumps",
    },
    "time": {
        "time": "clock",
        "sleep": "sleep",
        "strftime": "format_time",
    },
    "os": {
        "listdir": "os_list_dir",
        "mkdir": "os_mkdir",
        "rmdir": "os_rmdir",
        "getenv": "os_getenv",
        "getcwd": "os_cwd",
        "rename": "os_move_file",
        "remove": "os_delete_file",
        "system": "os_shell",
    },
    "urllib": {
        "request": {
            "urlopen": "http_get_simple",
        },
    },
}

# 嵌套模块映射：os.path.exists 等
NESTED_MODULES = {
    ("os", "path"): {
        "exists": "os_file_exists",
        "getsize": "os_file_size",
    },
}

# Scheme 预置函数（不是 C 函数，不走 foreign-procedure）
MATH_FUNCTIONS = {
    "sin", "cos", "tan", "log", "log2", "log10", "exp", "sqrt",
    "floor", "ceil", "round", "pow", "fmod",
    "sinh", "cosh", "tanh", "atan2", "asin", "acos", "atan",
    "abs",
}

PRELUDE_FUNCTIONS = {
    "make_float_array", "float_array_set", "float_array_ref",
    "float_array_free",
    "make_int_array", "int_array_set", "int_array_ref",
    "make_dict", "dict_get", "dict_get_or_empty", "dict_set",
    "file_open", "file_close", "file_read_all", "file_write", "file_exists",
    "http_get", "http_get_simple",
    "parse_json", "json_dumps", "now_ts", "format_time",
    "csv_parse", "csv_encode",
    "str_split", "str_join", "str_trim", "str_lower", "str_upper",
    "str_replace", "str_contains", "str_starts_with", "str_ends_with",
    "str_length", "str_slice",
    "os_list_dir", "os_getenv", "os_getcwd", "os_file_size",
    "os_file_exists", "os_move_file", "os_delete_file",
    "os_mkdir", "os_rmdir", "os_shell", "os_cwd",
    "re_match", "re_search",
    "random_seed", "random_int", "random_float", "random_range",
    "random_uniform", "random_choice",
    "string_to_float", "string_to_int", "string_of_int", "format_float", "list_length", "list_ref", "vec_ref", "tuple_ref",
    "cuda_gemm", "cuda_gemm_tn", "cuda_axpy", "cuda_dot", "cuda_copy",
    "sleep", "clock",
    "argv", "exit_program", "exit",
    "pi", "e",
    "py_list", "py_list_append", "py_list_ref", "py_list_length", "list_to_py_list", "list_append_str",
} | MATH_FUNCTIONS

def parse_extern_functions(code):
    """解析 extern fn 声明"""
    pattern = r'extern\s+fn\s+(\w+)\s*\((.*?)\)\s*->\s*(\w+)\s+from\s+"(\w+)"'
    for m in re.finditer(pattern, code, re.DOTALL):
        name = m.group(1)
        if name in PRELUDE_FUNCTIONS:
            # Scheme 预置函数，不走 FFI
            continue
        params_str = m.group(2)
        ret = m.group(3)
        lib = m.group(4)
        params = []
        for p in params_str.split(","):
            p = p.strip()
            if p:
                parts = p.split(":")
                pname = parts[0].strip()
                ptype = parts[1].strip() if len(parts) > 1 else "float"
                params.append((pname, ptype))
        EXTERN_FUNCTIONS[name] = {
            "ret": ret,
            "params": params,
            "lib": lib,
        }
    # 移除 extern 行（需要 DOTALL 匹配多行参数列表，但排除注释中的 extern fn）
    code = re.sub(r'(?m)^\s*extern\s+fn\s+.*?from\s+"\w+"', "", code, flags=re.DOTALL)
    return code


def parse_imports(tree):
    """解析 import / from ... import 语句，填充 MODULE_ALIASES 和 IMPORTED_NAMES"""
    for node in tree.body:
        if isinstance(node, ast.Import):
            for alias in node.names:
                # import numpy as np
                name = alias.name
                asname = alias.asname if alias.asname else name
                MODULE_ALIASES[asname] = name
        elif isinstance(node, ast.ImportFrom):
            module = node.module or ""
            for alias in node.names:
                name = alias.name
                asname = alias.asname if alias.asname else name
                IMPORTED_NAMES[asname] = module


def is_module_alias(name):
    return name in MODULE_ALIASES or name in BUILTIN_MODULES


def resolve_module_function(module_alias, attr):
    """把 module.func 解析为 Scheme 函数名，支持嵌套模块如 os.path.exists"""
    module = MODULE_ALIASES.get(module_alias, module_alias)
    mod_map = BUILTIN_MODULES.get(module)
    if mod_map and attr in mod_map:
        return mod_map[attr]
    return None


def resolve_nested_module(path, attr):
    """解析嵌套模块如 os.path.exists"""
    key = tuple(path)
    mod_map = NESTED_MODULES.get(key)
    if mod_map and attr in mod_map:
        return mod_map[attr]
    return None


def resolve_imported_name(name):
    """把 from 导入的裸函数名解析为 (module, scheme_fn)"""
    if name not in IMPORTED_NAMES:
        return None, None
    module = IMPORTED_NAMES[name]
    mod_map = BUILTIN_MODULES.get(module)
    if mod_map and name in mod_map:
        return module, mod_map[name]
    return module, name


# ====== 全局类型环境 ======
TYPE_ENV = {}

def parse_type_annotation(node):
    """从 ast.AnnAssign / ast.arg 解析 Python 类型字符串"""
    if node is None:
        return None
    ann = node.annotation
    if ann is None:
        return None
    if isinstance(ann, ast.Name):
        return ann.id
    if isinstance(ann, ast.Constant) and isinstance(ann.value, str):
        return ann.value
    if isinstance(ann, ast.Subscript):
        # list[int], list[float], array[float, N], Callable[[int], int]
        if isinstance(ann.value, ast.Name):
            base = ann.value.id
            if base == "list":
                if isinstance(ann.slice, ast.Name):
                    return f"list[{ann.slice.id}]"
                if isinstance(ann.slice, ast.Constant) and isinstance(ann.slice.value, str):
                    return f"list[{ann.slice.value}]"
            if base == "array":
                # array[float, N] -> array[float,N]
                if isinstance(ann.slice, ast.Tuple) and len(ann.slice.elts) == 2:
                    t = ann.slice.elts[0]
                    n = ann.slice.elts[1]
                    t_str = t.id if isinstance(t, ast.Name) else str(t.value)
                    n_str = str(n.id) if isinstance(n, ast.Name) else str(n.value)
                    return f"array[{t_str},{n_str}]"
            if base == "Callable":
                # Callable[[arg1, ...], ret] -> Callable[arg1,...,ret]
                if isinstance(ann.slice, ast.Tuple) and len(ann.slice.elts) == 2:
                    args_node = ann.slice.elts[0]
                    ret_node = ann.slice.elts[1]
                    if isinstance(args_node, ast.List):
                        arg_strs = []
                        for a in args_node.elts:
                            if isinstance(a, ast.Name):
                                arg_strs.append(a.id)
                            elif isinstance(a, ast.Constant) and isinstance(a.value, str):
                                arg_strs.append(a.value)
                        ret_str = ret_node.id if isinstance(ret_node, ast.Name) else str(ret_node.value)
                        return f"Callable[{','.join(arg_strs)},{ret_str}]"
    return None

def collect_function_types(node):
    """收集函数参数类型和函数体内 AnnAssign 类型到 TYPE_ENV（仅用于代码生成决策）"""
    # 参数类型
    for arg in node.args.args:
        t = parse_type_annotation(arg)
        if t:
            TYPE_ENV[mangle_name(arg.arg)] = t
    # 遍历函数体收集 AnnAssign
    for stmt in node.body:
        if isinstance(stmt, ast.AnnAssign):
            target = mangle_name(stmt.target.id) if isinstance(stmt.target, ast.Name) else None
            t = parse_type_annotation(stmt)
            if target and t:
                TYPE_ENV[target] = t
        elif isinstance(stmt, ast.FunctionDef):
            collect_function_types(stmt)


def collect_assigned_names(stmts):
    """递归收集语句列表中被赋值的变量名（不含嵌套函数定义内部）"""
    names = set()
    for stmt in stmts:
        if isinstance(stmt, (ast.Assign, ast.AnnAssign)):
            for t in (stmt.targets if isinstance(stmt, ast.Assign) else [stmt.target]):
                if isinstance(t, ast.Name):
                    names.add(t.id)
                elif isinstance(t, ast.Tuple):
                    for elt in t.elts:
                        if isinstance(elt, ast.Name):
                            names.add(elt.id)
                elif isinstance(t, ast.Subscript):
                    # subscript 赋值不引入新局部变量
                    pass
        elif isinstance(stmt, ast.AugAssign):
            if isinstance(stmt.target, ast.Name):
                names.add(stmt.target.id)
        elif isinstance(stmt, ast.For):
            if isinstance(stmt.target, ast.Name):
                names.add(stmt.target.id)
            names.update(collect_assigned_names(stmt.body))
            names.update(collect_assigned_names(stmt.orelse))
        elif isinstance(stmt, ast.While):
            names.update(collect_assigned_names(stmt.body))
            names.update(collect_assigned_names(stmt.orelse))
        elif isinstance(stmt, ast.If):
            names.update(collect_assigned_names(stmt.body))
            names.update(collect_assigned_names(stmt.orelse))
        elif isinstance(stmt, ast.With):
            for item in stmt.items:
                if item.optional_vars and isinstance(item.optional_vars, ast.Name):
                    names.add(item.optional_vars.id)
            names.update(collect_assigned_names(stmt.body))
        elif isinstance(stmt, ast.Try):
            names.update(collect_assigned_names(stmt.body))
            for handler in stmt.handlers:
                if handler.name:
                    names.add(handler.name)
                names.update(collect_assigned_names(handler.body))
            names.update(collect_assigned_names(stmt.orelse))
            names.update(collect_assigned_names(stmt.finalbody))
        # 嵌套函数定义不展开（它们有自己的作用域）
    return names


def infer_expr_type(node):
    """基于 TYPE_ENV 推断表达式类型（仅用于代码生成优化，不参与类型检查）"""
    if node is None:
        return None
    if isinstance(node, ast.List):
        return "list"
    if isinstance(node, ast.Constant):
        if isinstance(node.value, bool):
            return "bool"
        if isinstance(node.value, int):
            return "int"
        if isinstance(node.value, float):
            return "float"
        if isinstance(node.value, str):
            return "str"
        return None
    if isinstance(node, ast.Name):
        return TYPE_ENV.get(mangle_name(node.id))
    if isinstance(node, ast.Subscript):
        vt = infer_expr_type(node.value)
        if vt == "list":
            return "Any"
        if vt and str(vt).startswith("list["):
            return str(vt)[5:-1]
        if vt and str(vt).startswith("vector["):
            return str(vt)[7:-1]
        if vt == "str":
            return "str"
        return None
    if isinstance(node, ast.BinOp):
        lt = infer_expr_type(node.left)
        rt = infer_expr_type(node.right)
        if (lt and str(lt).startswith("list")) or (rt and str(rt).startswith("list")):
            return lt or rt
        if lt == "int" and rt == "int":
            return "int"
        if lt in ("int", "float") and rt in ("int", "float"):
            return "float"
        if lt == "str" or rt == "str":
            return "str"
        return None
    if isinstance(node, ast.Tuple):
        elem_types = [infer_expr_type(e) for e in node.elts]
        if all(t and str(t).startswith("list") for t in elem_types):
            return "list"
        if any(t and str(t).startswith("list") for t in elem_types):
            return "tuple"
        return "tuple" if any(elem_types) else None
    if isinstance(node, ast.UnaryOp):
        if isinstance(node.op, ast.Not):
            return "bool"
        return infer_expr_type(node.operand)
    if isinstance(node, ast.Compare):
        return "bool"
    if isinstance(node, ast.Call):
        # 根据函数名推断返回类型（简化）
        if isinstance(node.func, ast.Name):
            name = mangle_name(node.func.id)
            if name in RECORD_TYPES:
                return name
            if name in ("Ok", "Error", "Some"):
                return name.lower()
            if name in ("int", "len"):
                return "int"
            if name == "float":
                return "float"
            if name == "bool":
                return "bool"
            if name == "make_float_array":
                return "list[float]"
            # 用户函数：从 FUNCTION_SIGS 推断返回类型
            unmangled = node.func.id
            if unmangled in FUNCTION_SIGS:
                _, fret = FUNCTION_SIGS[unmangled]
                if fret:
                    return str(fret)
            # IR 构造器视为通用对象/元组
            if unmangled in ("EConst", "EVar", "ECall", "EUnary", "EBinop", "SExpr", "SLet", "SSet", "SReturn", "SIf", "SWhile", "SFor", "IRFunc"):
                return "Any"
            # 处理 from np import array 后调用 array(...)
            _, scheme_fn = resolve_imported_name(name)
            if scheme_fn == "np-array":
                return "list[float]"
            if scheme_fn in ("torch-add", "torch-mul", "torch-sub", "torch-matmul", "torch-clone"):
                return "torch-tensor"
            if scheme_fn == "torch-to-list":
                return "list[float]"
            if scheme_fn == "torch-available":
                return "bool"
        if isinstance(node.func, ast.Attribute):
            obj = None
            if isinstance(node.func.value, ast.Name):
                obj = node.func.value.id
            attr = node.func.attr
            if is_module_alias(obj):
                scheme_fn = resolve_module_function(obj, attr)
                if scheme_fn == "np-array":
                    return "list[float]"
                if scheme_fn in ("np-zeros", "np-ones"):
                    return "list[float]"
                if scheme_fn == "torch-tensor":
                    return "torch-tensor"
                if scheme_fn in ("torch-zeros", "torch-ones", "torch-empty"):
                    return "torch-tensor"
                if scheme_fn in ("torch-add", "torch-mul", "torch-sub", "torch-matmul", "torch-clone"):
                    return "torch-tensor"
                if scheme_fn == "torch-to-list":
                    return "vector[float]"
                if scheme_fn == "torch-available":
                    return "bool"
                # SD / JIT / DDPM extensions
                if scheme_fn in ("torch-sd-unet-forward", "torch-load-image",
                                 "torch-ddpm-betas", "torch-ddpm-add-noise",
                                 "torch-jit-forward", "torch-to-cuda", "torch-to-cpu"):
                    return "torch-tensor"
                if scheme_fn in ("torch-save-image", "torch-jit-delete"):
                    return "void"
                if scheme_fn in ("torch-jit-load",):
                    return "ptr"
                if scheme_fn == "torch-save-state-dict":
                    return "int"
                if scheme_fn in ("sin", "cos", "tan", "log", "log2", "log10", "exp", "sqrt", "abs", "pow", "fmod",
                                  "floor", "ceil", "round", "sinh", "cosh", "tanh", "atan2", "asin", "acos", "atan"):
                    return "float"
                if scheme_fn == "random_float" or scheme_fn == "random_uniform":
                    return "float"
                if scheme_fn == "random_range" or scheme_fn == "random_randint" or scheme_fn == "random_int":
                    return "int"
                if scheme_fn == "parse_json":
                    return "dict"
                if scheme_fn == "json_dumps":
                    return "str"
                if scheme_fn in ("clock",):
                    return "float"
                if scheme_fn in ("os_cwd", "os_getenv"):
                    return "str"
                if scheme_fn in ("os_file_exists",):
                    return "bool"
                if scheme_fn in ("os_file_size",):
                    return "int"
                if scheme_fn in ("os_list_dir",):
                    return "list[str]"
                if scheme_fn == "http_get_simple":
                    return "str"
    if isinstance(node, ast.Subscript):
        vt = infer_expr_type(node.value)
        if vt == "str":
            return "str"
        if vt and str(vt).startswith("list["):
            inner = str(vt)[5:-1]
            return inner
        if vt and str(vt).startswith("vector["):
            inner = str(vt)[7:-1]
            return inner
        if vt and str(vt).startswith("array["):
            parts = str(vt)[6:-1].split(",")
            if len(parts) == 2:
                return parts[0]
    if isinstance(node, ast.List):
        if all(isinstance(e, ast.Constant) and isinstance(e.value, int) for e in node.elts):
            return "list[int]"
        if all(isinstance(e, ast.Constant) and isinstance(e.value, float) for e in node.elts):
            return "list[float]"
        return "list"
    return None


def translate_binop(op_name, left_node, right_node):
    """根据操作数类型生成特化运算符"""
    left = translate_expr(left_node)
    right = translate_expr(right_node)
    lt = infer_expr_type(left_node)
    rt = infer_expr_type(right_node)
    is_int = (lt == "int" and rt == "int")
    is_float = (lt in ("int", "float") and rt in ("int", "float"))
    is_str = (lt == "str" and rt == "str")

    op_map = {
        "Add":    ("fx+", "fl+", "+"),
        "Sub":    ("fx-", "fl-", "-"),
        "Mult":   ("fx*", "fl*", "*"),
        "Div":    ("fx/", "fl/", "/"),
        "FloorDiv": ("fxdiv", "fldiv", "quotient"),
        "Mod":    ("fxmod", "flmod", "mod"),
        "Pow":    ("fxexpt", "flexpt", "expt"),
    }
    fx_op, fl_op, generic = op_map.get(op_name, (None, None, op_name.lower()))

    if op_name == "Add":
        l_list = lt and str(lt).startswith("list")
        r_list = rt and str(rt).startswith("list")
        if l_list and r_list:
            return f"(py-list-concat {left} {right})"
        if l_list or r_list:
            return f"(py-list-append {left} {right})"
    if is_int and fx_op:
        return f"({fx_op} {left} {right})"
    if is_float and fl_op:
        return f"({fl_op} {left} {right})"
    if (is_str or lt == "str" or rt == "str") and op_name == "Add":
        return f"(string-append {left} {right})"
    # 张量二元运算：任一侧是张量表达式/变量 → torch-tensor-<op>（带标量提升）
    if op_name in ("Add", "Sub", "Mult", "Div"):
        if expr_is_tensor(left_node) or expr_is_tensor(right_node):
            tname = {
                "Add": "add", "Sub": "sub", "Mult": "mul", "Div": "div",
            }[op_name]
            return f"(torch-tensor-{tname} {left} {right})"
    return f"({generic} {left} {right})"


def translate_compare(op, left_node, right_node):
    """根据操作数类型生成特化比较运算符"""
    left = translate_expr(left_node)
    right = translate_expr(right_node)
    lt = infer_expr_type(left_node)
    rt = infer_expr_type(right_node)
    is_int = (lt == "int" and rt == "int")
    is_float = (lt in ("int", "float") and rt in ("int", "float"))
    is_str = (lt == "str" and rt == "str")

    op_map_num = {
        "Lt":   ("fx<", "fl<", "<"),
        "LtE":  ("fx<=", "fl<=", "<="),
        "Gt":   ("fx>", "fl>", ">"),
        "GtE":  ("fx>=", "fl>=", ">="),
        "Eq":   ("fx=", "fl=", "="),
        "NotEq":(None, None, None),
    }
    op_map_str = {
        "Lt":   "string<?",
        "LtE":  "string<=?",
        "Gt":   "string>?",
        "GtE":  "string>=?",
        "Eq":   "string=?",
        "NotEq":None,
    }
    if type(op).__name__ == "NotEq":
        inner = translate_compare(ast.Eq(), left_node, right_node)
        return f"(not {inner})"
    if is_int:
        fx_op, fl_op, generic = op_map_num.get(type(op).__name__, (None, None, None))
        if fx_op:
            return f"({fx_op} {left} {right})"
    if is_float:
        fx_op, fl_op, generic = op_map_num.get(type(op).__name__, (None, None, None))
        if fl_op:
            return f"({fl_op} {left} {right})"
    if (is_str or lt == "str" or rt == "str"):
        str_op = op_map_str.get(type(op).__name__)
        if str_op:
            return f"({str_op} {left} {right})"
    fx_op, fl_op, generic = op_map_num.get(type(op).__name__, (None, None, None))
    return f"({generic} {left} {right})"


def translate_aug_assign(node):
    """翻译 AugAssign (i += 1, s *= 2 等)"""
    target = mangle_name(node.target.id) if isinstance(node.target, ast.Name) else None
    if target:
        return f"(set! {target} {translate_binop(type(node.op).__name__, node.target, node.value)})"
    return f"(void)"

def translate_type(py_type):
    """Python 类型 → C 类型（用于 FFI）"""
    # list[float] → void* (double*), list[int] → void* (int64_t*)
    if str(py_type).startswith("list[") or py_type == "list":
        return "void*"
    base = str(py_type).replace("[]", "")
    return TYPE_MAP.get(base, "void*")


def make_int_vector(n, init_expr=None):
    """生成创建 int vector 的 Scheme 表达式"""
    if init_expr:
        return f"(make-vector {n} {init_expr})"
    return f"(make-vector {n} 0)"


def make_float_vector(n, init_expr=None):
    """生成创建 float vector 的 Scheme 表达式"""
    if init_expr:
        return f"(make-fxvector {n} {init_expr})" if False else f"(make-vector {n} {init_expr})"
    return f"(make-vector {n} 0.0)"


def translate_stmt(node, bindings=None):
    """翻译一条语句
    bindings: 收集 let 绑定，用于在函数级别统一包装
    """
    if bindings is None:
        bindings = []
    if isinstance(node, ast.FunctionDef):
        return translate_function(node, bindings)
    elif isinstance(node, ast.Return):
        val = translate_expr(node.value) if node.value else "#f"
        return val
    elif isinstance(node, ast.AnnAssign):
        target = mangle_name(node.target.id) if isinstance(node.target, ast.Name) else None
        if target and node.value:
            val = translate_expr(node.value)
            bindings.append((target, val))
            return f"  {target}"
        return f"  ;; annot-assign {ast.dump(node)}"
    elif isinstance(node, ast.Assign):
        targets = node.targets
        if len(targets) == 1 and isinstance(targets[0], ast.Tuple) and all(isinstance(e, ast.Name) for e in targets[0].elts):
            # a, b = expr（expr 是 Scheme vector）→ 逐元素 vector-ref
            tmp = f"__unpack_{node.lineno}"
            names = [e.id for e in targets[0].elts]
            val = translate_expr(node.value)
            sets = " ".join(f"(set! {n} (vector-ref {tmp} {i}))" for i, n in enumerate(names))
            bindings.append((tmp, val))
            return f"  ;; tuple-unpack\n  (begin {sets})"
        if len(targets) == 1 and isinstance(targets[0], ast.Name):
            name = targets[0].id
            val = translate_expr(node.value)
            bindings.append((name, val))
            return f"  {name}"
        return f"  ;; assign {ast.dump(node)}"
    elif isinstance(node, ast.Expr):
        return f"  {translate_expr(node.value)}"
    elif isinstance(node, ast.If):
        test = translate_expr(node.test)
        body = "\n".join(translate_stmt(s) for s in node.body)
        orelse = node.orelse
        if orelse:
            else_body = "\n".join(translate_stmt(s) for s in orelse)
            return f"  (if {test}\n    (begin\n{body})\n    (begin\n{else_body}))"
        else:
            return f"  (if {test}\n    (begin\n{body}))"
    elif isinstance(node, ast.While):
        test = translate_expr(node.test)
        body = "\n".join(translate_stmt(s) for s in node.body)
        return f"  (let loop ()\n    (if {test}\n      (begin\n{body}\n        (loop))))"
    elif isinstance(node, ast.For):
        target = mangle_name(node.target.id) if isinstance(node.target, ast.Name) else "i"
        iter_expr = node.iter
        body = "\n".join(translate_stmt(s) for s in node.body)
        # for i in range(n): → 用 do 循环
        if isinstance(iter_expr, ast.Call) and hasattr(iter_expr.func, 'id') and iter_expr.func.id == 'range':
            args = iter_expr.args
            if len(args) == 1:
                n = translate_expr(args[0])
                return f"  (do (({target} 0 (+ {target} 1))) ((>= {target} {n}))\n{body})"
            elif len(args) == 2:
                start = translate_expr(args[0])
                end = translate_expr(args[1])
                return f"  (do (({target} {start} (+ {target} 1))) ((>= {target} {end}))\n{body})"
        return f"  ;; for loop (untranslated)"
    elif isinstance(node, ast.AugAssign):
        target = mangle_name(node.target.id) if isinstance(node.target, ast.Name) else "x"
        val = translate_expr(node.value)
        op = node.op
        if isinstance(op, ast.Add):
            return f"  (set! {target} (+ {target} {val}))"
        elif isinstance(op, ast.Sub):
            return f"  (set! {target} (- {target} {val}))"
        elif isinstance(op, ast.Mult):
            return f"  (set! {target} (* {target} {val}))"
        return f"  ;; aug-assign"
    else:
        return f"  ;; {type(node).__name__}: {ast.dump(node)}"


def has_return(stmts):
    """递归检查语句块中是否包含 return 语句"""
    for s in stmts:
        if isinstance(s, ast.Return):
            return True
        if isinstance(s, ast.If):
            if has_return(s.body) or has_return(s.orelse):
                return True
        if isinstance(s, (ast.For, ast.While, ast.With)):
            if has_return(s.body):
                return True
        if isinstance(s, ast.Try):
            if has_return(s.body):
                return True
            for h in s.handlers:
                if has_return(h.body):
                    return True
    return False


def translate_block(stmts):
    """翻译一个语句块（if/while 体），正确处理 set! 赋值"""
    exprs = []
    for s in stmts:
        if isinstance(s, (ast.Assign, ast.AnnAssign)):
            target = None
            val = None
            destructure_done = False
            if isinstance(s, ast.AnnAssign):
                target = mangle_name(s.target.id) if isinstance(s.target, ast.Name) else None
                val = translate_expr(s.value) if s.value else "#f"
            else:
                if len(s.targets) == 1 and isinstance(s.targets[0], ast.Name):
                    target = s.targets[0].id
                    val = translate_expr(s.value)
                elif len(s.targets) == 1 and isinstance(s.targets[0], ast.Tuple):
                    # 元组解构：a, b = expr → (let ((tmp expr)) (set! a (vector-ref tmp 0)) ...)
                    t = s.targets[0]
                    tmp = "__tmp_" + str(len(exprs))
                    tmp_val = translate_expr(s.value)
                    if isinstance(s.value, ast.Tuple):
                        elems = [translate_expr(e) for e in s.value.elts]
                        tmp_val = f"(vector {' '.join(elems)})"
                    binds = []
                    for idx, elt in enumerate(t.elts):
                        if isinstance(elt, ast.Name):
                            binds.append(f"(set! {mangle_name(elt.id)} (vector-ref {tmp} {idx}))")
                    exprs.append(f"(let (({tmp} {tmp_val})) {' '.join(binds)})")
                    destructure_done = True
                elif len(s.targets) == 1 and isinstance(s.targets[0], ast.Subscript):
                    t = s.targets[0]
                    d = translate_expr(t.value)
                    k = translate_expr(t.slice)
                    v = translate_expr(s.value)
                    exprs.append(f"(dict-set! {d} {k} {v})")
                    destructure_done = True
            if target and val:
                # 从右侧表达式推断目标变量类型，仅用于辅助代码生成
                inferred = infer_expr_type(s.value)
                if inferred:
                    TYPE_ENV[target] = inferred
                exprs.append(f"(set! {target} {val})")
            elif not destructure_done:
                exprs.append(f";; {ast.dump(s)}")
        elif isinstance(s, ast.Expr):
            exprs.append(translate_expr(s.value))
        elif isinstance(s, ast.Return):
            val = translate_expr(s.value) if s.value else "#f"
            exprs.append(f"(__return__ {val})")
        elif isinstance(s, ast.AugAssign):
            exprs.append(translate_aug_assign(s))
        elif isinstance(s, ast.If):
            # 嵌套 if
            test = translate_expr(s.test)
            inner_then = translate_block(s.body)
            if s.orelse:
                inner_else = translate_block(s.orelse)
                exprs.append(f"(if {test}\n        (begin {' '.join(inner_then)})\n        (begin {' '.join(inner_else)}))")
            else:
                exprs.append(f"(if {test}\n        (begin {' '.join(inner_then)}))")
        elif isinstance(s, ast.While):
            test = translate_expr(s.test)
            body = translate_block(s.body)
            exprs.append(f"(let loop () (if {test} (begin {' '.join(body)} (loop))))")
        elif isinstance(s, ast.With):
            # with 在 block 内简化为直接执行 body
            exprs.extend(translate_block(s.body))
        elif isinstance(s, ast.Try):
            # try/except 语法糖：使用 guard 捕获异常
            body_scheme = " ".join(translate_block(s.body))
            handler_body = ""
            if s.handlers:
                handler_body = " ".join(translate_block(s.handlers[0].body))
            else:
                handler_body = "(void)"
            exprs.append(f"(guard (e (else {handler_body})) {body_scheme})")
        elif isinstance(s, ast.Raise):
            if s.exc and isinstance(s.exc, ast.Call) and isinstance(s.exc.func, ast.Name):
                msg = ""
                if s.exc.args:
                    msg = translate_expr(s.exc.args[0])
                exprs.append(f"(error '{s.exc.func.id} {msg})")
            elif s.exc and isinstance(s.exc, ast.Name):
                exprs.append(f"(error '{s.exc.id} \"raised\")")
            else:
                exprs.append("(error 'raise \"raised\")")
        elif isinstance(s, ast.Assert):
            test = translate_expr(s.test)
            msg = translate_expr(s.msg) if s.msg else "\"assertion failed\""
            exprs.append(f"(if (not {test}) (error 'assert {msg}))")
        elif isinstance(s, ast.Pass):
            exprs.append("(void)")
        elif isinstance(s, ast.Pass):
            exprs.append("(void)")
        elif isinstance(s, ast.Delete):
            exprs.append(f";; del: {ast.dump(s)}")
        elif isinstance(s, ast.Call):
            exprs.append(translate_expr(s))
        else:
            exprs.append(f";; {type(s).__name__}: {ast.dump(s)}")
    return exprs


WARNINGS = []

def warn(msg, node=None):
    """收集警告"""
    if node and hasattr(node, 'lineno'):
        lineno = getattr(node, 'lineno', '?')
        WARNINGS.append(f"  ⚠ {msg} at line {lineno}")
    else:
        WARNINGS.append(f"  ⚠ {msg}")

def format_loc(node):
    """返回源码位置字符串"""
    if node and hasattr(node, 'lineno'):
        return f" (line {node.lineno})"
    return ""

class StaticPyTypeError(Exception):
    """StaticPy 类型检查错误（可被前端捕获，不强制退出进程）"""
    def __init__(self, node, msg):
        self.node = node
        self.msg = msg
        self.loc = format_loc(node)
        super().__init__(f"StaticPy type error{self.loc}: {msg}")


# 类型检查模式：'strict'（默认）出错即退出；'warn' 只打印警告继续编译
TYPECHECK_MODE = "strict"
TYPE_WARNINGS = []

# 在 warn 模式下也会阻止 Scheme 生成的“硬错误”集合
# 这些错误如果进入后端，必然导致 Chez 编译/运行失败
WARN_BLOCKING_ERRORS = {
    "undefined name",
    "missing main function",
}

def set_typecheck_mode(mode):
    global TYPECHECK_MODE
    TYPECHECK_MODE = mode

def _error_key(msg):
    """提取错误消息前缀，用于判断是否为硬错误"""
    for key in WARN_BLOCKING_ERRORS:
        if msg.startswith(key) or key in msg:
            return key
    return None

def typecheck_error(node, msg):
    """输出类型检查错误或警告；strict 模式抛出异常，warn 模式对硬错误仍抛出"""
    loc = format_loc(node)
    if TYPECHECK_MODE == "warn" and _error_key(msg) is None:
        TYPE_WARNINGS.append(f"{loc}: {msg}")
        sys.stderr.write(f"StaticPy type warning{loc}: {msg}\n")
    else:
        sys.stderr.write(f"StaticPy type error{loc}: {msg}\n")
        raise StaticPyTypeError(node, msg)

def typecheck_warn(node, msg):
    """总是作为警告输出"""
    loc = format_loc(node)
    TYPE_WARNINGS.append(f"{loc}: {msg}")
    sys.stderr.write(f"StaticPy type warning{loc}: {msg}\n")


def collect_record_types(tree):
    """收集模块中所有 dataclass 类型定义及其字段类型"""
    for node in tree.body:
        if isinstance(node, ast.ClassDef) and is_dataclass_class(node):
            fields = []
            field_types = {}
            for item in node.body:
                if isinstance(item, ast.AnnAssign) and isinstance(item.target, ast.Name):
                    fname = item.target.id
                    fields.append(fname)
                    ft = parse_type(item)
                    if ft:
                        field_types[fname] = ft
            RECORD_TYPES[node.name] = fields
            RECORD_FIELDS[node.name] = field_types


def collect_function_signatures(tree):
    """收集所有函数签名：函数名 -> ([arg_type, ...], return_type)"""
    for node in tree.body:
        if isinstance(node, ast.FunctionDef):
            arg_types = []
            for arg in node.args.args:
                arg_types.append(parse_type(arg.annotation))
            ret_type = parse_type(node.returns)
            FUNCTION_SIGS[node.name] = (arg_types, ret_type)


def is_enum_class(node):
    """检测是否是枚举类：继承 Enum 或所有成员都是整型常量赋值"""
    if not isinstance(node, ast.ClassDef):
        return False
    for base in node.bases:
        if isinstance(base, ast.Name) and base.id == "Enum":
            return True
    # 无继承但所有 body 都是 Assign Constant(int)
    if all(isinstance(item, ast.Assign) and len(item.targets) == 1
           and isinstance(item.targets[0], ast.Name)
           and isinstance(item.value, ast.Constant)
           and isinstance(item.value.value, int)
           for item in node.body):
        return True
    return False


def is_dataclass_class(node):
    """检测是否是 dataclass-style 记录类：body 全为 AnnAssign"""
    if not isinstance(node, ast.ClassDef):
        return False
    return all(isinstance(item, ast.AnnAssign) for item in node.body)


def translate_dataclass(node):
    """翻译 dataclass-style 类为 Scheme define-record-type"""
    name = node.name
    fields = []
    for item in node.body:
        if isinstance(item, ast.AnnAssign) and isinstance(item.target, ast.Name):
            fields.append(item.target.id)
    if not fields:
        return f";; class {name} (no fields)"
    field_str = " ".join(fields)
    return "\n".join([f"(define-record-type {name}", f"  (fields {field_str}))"])


def translate_enum(node):
    """翻译枚举类为 Scheme 常量定义"""
    name = node.name
    lines = [f";; enum {name}"]
    for item in node.body:
        if isinstance(item, ast.Assign) and len(item.targets) == 1 and isinstance(item.targets[0], ast.Name):
            cname = item.targets[0].id
            val = translate_expr(item.value)
            lines.append(f"(define {name}_{cname} {val})")
    return "\n".join(lines)


def translate_class(node):
    """翻译类定义（dataclass 或 enum）"""
    if is_enum_class(node):
        return translate_enum(node)
    if is_dataclass_class(node):
        return translate_dataclass(node)
    return f";; unsupported class {node.name}"


def typecheck_function(node, function_arities, module_env=None):
    """函数级类型检查：参数、返回值、赋值、运算、调用、下标、字段"""
    module_env = module_env or {}
    name = node.name
    defined = set(arg.arg for arg in node.args.args)
    builtin_names = {"print", "len", "range", "int", "float", "str", "bool",
                     "make_array", "make_float_array", "make_int_array",
                     "float_array_set", "float_array_ref",
                     "int_array_set", "int_array_ref",
                     "make_dict", "dict_get", "dict_get_or_empty", "dict_set",
                     "to_list", "available", "Ok", "Error", "Some", "none",
                     "is_ok", "is_error", "is_some", "is_none",
                     "unwrap", "unwrap_or", "unwrap_error", "EConst", "EVar", "EBinop",
                     "EUnary", "ECall", "IRStmt", "SLet", "SSet", "SReturn", "SExpr",
                     "SIf", "SWhile", "SFor", "IRFunc", "IRExpr", "env", "lt", "rt",
                     "indent", "value", "name", "op", "operand", "func", "args",
                     "expr", "c", "v", "src", "out", "i", "n", "start", "pos", "tok",
                     "s", "f", "stmts", "parts", "bindings", "body_expr", "tokens",
                     "ln", "rn", "left", "right", "cond", "then_expr", "else_expr",
                     "stop", "funcs", "func", "params", "scm", "stmt", "lv", "arg",
                     "a", "p", "path", "inp", "source", "target", "result", "inner",
                     "done", "ty", "end_tok", "nxt", "pos2", "def_tok", "lparen",
                     "arrow", "ret", "body", "first", "rest", "outp", "sep_str", "lst", "val"}

    # 局部类型环境
    env = dict(module_env)
    for arg in node.args.args:
        t = parse_type(arg.annotation)
        if t:
            env[arg.arg] = t
        else:
            # 无类型标注的参数视为 Any
            env[arg.arg] = Type("Any")

    # 注册嵌套函数签名，使外层可见
    for stmt in node.body:
        if isinstance(stmt, ast.FunctionDef):
            arg_types = [parse_type(arg.annotation) for arg in stmt.args.args]
            ret_type = parse_type(stmt.returns)
            env[stmt.name] = Type("arrow", arg_types + [ret_type])

    # 函数返回类型
    ret_type = parse_type(node.returns)

    def lookup(name):
        if name in env:
            return env[name]
        if name in module_env:
            return module_env[name]
        return None

    def infer_binop(op, lt, rt):
        if lt is None or rt is None:
            return None
        op_name = type(op).__name__
        if op_name in BUILTIN_BINOP_RULES:
            allowed, result_fn = BUILTIN_BINOP_RULES[op_name]
            if allowed is not None:
                if lt.base != allowed or rt.base != allowed:
                    typecheck_error(node, f"operator '{op_name}' requires {allowed}, got '{lt}' and '{rt}'")
            result = result_fn(lt, rt)
            if result is None and lt.base != "Any" and rt.base != "Any":
                typecheck_error(node, f"operator '{op_name}' not supported for types '{lt}' and '{rt}'")
            return result
        return None

    def check_expr(expr):
        if expr is None:
            return None
        if isinstance(expr, ast.Constant):
            v = expr.value
            if isinstance(v, bool):
                return Type("bool")
            if isinstance(v, int):
                return Type("int")
            if isinstance(v, float):
                return Type("float")
            if isinstance(v, str):
                return Type("str")
            if v is None:
                return Type("none")
            return None
        if isinstance(expr, ast.Name):
            t = lookup(expr.id)
            if t is None and expr.id not in builtin_names and expr.id not in BUILTIN_MODULES \
                    and expr.id not in IMPORTED_NAMES and expr.id not in RECORD_TYPES:
                typecheck_error(expr, f"undefined name '{expr.id}'")
            return t
        if isinstance(expr, ast.Attribute):
            # 字段访问：p.x
            if isinstance(expr.value, ast.Name):
                vtype = lookup(expr.value.id)
                if vtype and vtype.base in RECORD_FIELDS:
                    ft = RECORD_FIELDS[vtype.base].get(expr.attr)
                    if ft:
                        return ft
                    typecheck_error(expr, f"record '{vtype.base}' has no field '{expr.attr}'")
            # module.attr：返回未知类型
            return None
        if isinstance(expr, ast.UnaryOp):
            if isinstance(expr.op, ast.Not):
                check_expr(expr.operand)
                return Type("bool")
            t = check_expr(expr.operand)
            if t and t.base not in ("int", "float", "Any"):
                typecheck_error(expr, f"unary operator not supported for type '{t}'")
            return t
        if isinstance(expr, ast.BinOp):
            lt = check_expr(expr.left)
            rt = check_expr(expr.right)
            return infer_binop(expr.op, lt, rt)
        if isinstance(expr, ast.Compare):
            check_expr(expr.left)
            for c in expr.comparators:
                check_expr(c)
            return Type("bool")
        if isinstance(expr, ast.BoolOp):
            for v in expr.values:
                check_expr(v)
            return Type("bool")
        if isinstance(expr, ast.IfExp):
            check_expr(expr.test)
            bt = check_expr(expr.body)
            et = check_expr(expr.orelse)
            if bt and et and not is_subtype(bt, et) and not is_subtype(et, bt):
                typecheck_error(expr, f"branches have incompatible types '{bt}' and '{et}'")
            return bt or et
        if isinstance(expr, ast.List):
            elem_types = [check_expr(e) for e in expr.elts]
            if elem_types:
                first = elem_types[0]
                if all(t == first for t in elem_types):
                    return Type("list", [first])
            return Type("list", [Type("?")])
        if isinstance(expr, ast.Tuple):
            elem_types = [check_expr(e) for e in expr.elts]
            if all(t is not None for t in elem_types):
                return Type("tuple", elem_types)
            return Type("tuple", [Type("Any")] * len(elem_types))
        if isinstance(expr, ast.Dict):
            return Type("dict")
        if isinstance(expr, ast.Subscript):
            vt = check_expr(expr.value)
            idx_t = check_expr(expr.slice)
            if isinstance(expr.slice, ast.Slice):
                return vt
            if vt and vt.base == "str":
                if idx_t and idx_t.base != "int":
                    typecheck_error(expr, f"string index must be int, got '{idx_t}'")
                return Type("str")
            if vt and vt.base in ("list", "array"):
                if idx_t and idx_t.base != "int" and idx_t.base != "Any":
                    typecheck_error(expr, f"index must be int, got '{idx_t}'")
                if vt.params and vt.params[0].base != "Any":
                    return vt.params[0]
            return None
        if isinstance(expr, ast.Call):
            return check_call(expr)
        if isinstance(expr, ast.JoinedStr):
            for v in expr.values:
                check_expr(v) if isinstance(v, ast.FormattedValue) else None
            return Type("str")
        return None

    def check_call(expr):
        func = expr.func
        arg_types = [check_expr(a) for a in expr.args]
        if isinstance(func, ast.Name):
            fname = func.id
            # 构造函数
            if fname in RECORD_FIELDS:
                fields = RECORD_FIELDS[fname]
                expected_types = list(fields.values())
                if len(arg_types) != len(expected_types):
                    typecheck_error(expr, f"'{fname}' expects {len(expected_types)} fields, got {len(arg_types)}")
                for i, (at, et) in enumerate(zip(arg_types, expected_types)):
                    if at and not is_subtype(at, et):
                        typecheck_error(expr, f"field {i+1} of '{fname}' expects '{et}', got '{at}'")
                return Type(fname)
            # 用户函数签名检查
            if fname in FUNCTION_SIGS:
                expected_types, fret = FUNCTION_SIGS[fname]
                if len(arg_types) != len(expected_types):
                    typecheck_error(expr, f"'{fname}' expects {len(expected_types)} args, got {len(arg_types)}")
                for i, (at, et) in enumerate(zip(arg_types, expected_types)):
                    if at and et and not is_subtype(at, et):
                        typecheck_error(expr, f"argument {i+1} of '{fname}' expects '{et}', got '{at}'")
                return fret
            # 局部变量/参数为函数值（Callable/arrow 类型）
            local_t = lookup(fname)
            if local_t and local_t.base in ("Callable", "arrow") and local_t.params:
                expected_types = local_t.params[:-1]
                fret = local_t.params[-1]
                if len(arg_types) != len(expected_types):
                    typecheck_error(expr, f"'{fname}' expects {len(expected_types)} args, got {len(arg_types)}")
                for i, (at, et) in enumerate(zip(arg_types, expected_types)):
                    if at and et and not is_subtype(at, et):
                        typecheck_error(expr, f"argument {i+1} of '{fname}' expects '{et}', got '{at}'")
                return fret
            # 内置函数 / from...import 函数返回类型
            _, scheme_fn = resolve_imported_name(fname)
            ret = BUILTIN_FN_RETURN_TYPES.get(fname)
            if ret is None and scheme_fn:
                ret = MODULE_FN_RETURN_TYPES.get(scheme_fn)
            if ret is not None:
                return ret
            if fname in ("Ok", "Some"):
                return Type(fname.lower(), arg_types[:1] if arg_types else [Type("?")])
            if fname == "Error":
                return Type("error", arg_types[:1] if arg_types else [Type("?")])
            if fname in ("is_ok", "is_error", "is_some", "is_none"):
                return Type("bool")
            if fname in ("unwrap", "unwrap_or"):
                return arg_types[0].params[0] if arg_types and arg_types[0] and arg_types[0].params else None
            if fname == "make_float_array":
                return Type("list", [Type("float")])
            if fname == "make_int_array":
                return Type("list", [Type("int")])
            if fname in ("print",):
                return Type("none")
            if fname == "range":
                return Type("range")
            return None
        if isinstance(func, ast.Attribute):
            # module.fn：利用模块函数返回类型映射
            for arg in expr.args:
                check_expr(arg)
            obj = None
            if isinstance(func.value, ast.Name):
                obj = func.value.id
            if isinstance(func.value, ast.Attribute):
                obj = translate_expr(func.value)
            attr = func.attr
            scheme_fn = None
            if is_module_alias(obj):
                scheme_fn = resolve_module_function(obj, attr)
            elif isinstance(func.value, ast.Attribute) and isinstance(func.value.value, ast.Name):
                top = func.value.value.id
                mid = func.value.attr
                if is_module_alias(top):
                    scheme_fn = resolve_nested_module((top, mid), attr)
            elif obj in BUILTIN_MODULES:
                scheme_fn = BUILTIN_MODULES[obj].get(attr)
            if scheme_fn in MODULE_FN_RETURN_TYPES:
                return MODULE_FN_RETURN_TYPES[scheme_fn]
            return None
        return None

    def check_stmt(stmt):
        if isinstance(stmt, ast.FunctionDef):
            # 嵌套函数：继承外层 env 作为 module_env，使其能访问外层参数/局部变量
            typecheck_function(stmt, function_arities, module_env=env)
            return
        if isinstance(stmt, ast.Assign):
            val_t = check_expr(stmt.value)
            if len(stmt.targets) == 1:
                target = stmt.targets[0]
                if isinstance(target, ast.Name):
                    declared = lookup(target.id)
                    if declared and declared.base != "Any" and val_t and val_t.base != "Any" and not is_subtype(val_t, declared):
                        typecheck_error(stmt, f"cannot assign '{val_t}' to variable '{target.id}' of type '{declared}'")
                    # 渐进式类型规则：
                    # - 有显式非 Any 标注：保持声明类型（已写入 env）
                    # - 声明为 Any：保持 Any，不收紧
                    # - 无声明：从右侧推断；推断不出设为 Any
                    if declared is None:
                        # 无显式标注：推断为 Any（渐进式类型），不根据首次赋值收紧
                        env[target.id] = Type("Any")
                    # 否则 declared 存在（Any 或具体类型），保持不变
                elif isinstance(target, ast.Tuple):
                    # 元组解构：每个元素从 tuple 类型推断或设为 Any
                    if val_t and val_t.base == "tuple":
                        for idx, elt in enumerate(target.elts):
                            if isinstance(elt, ast.Name):
                                et = val_t.params[idx] if idx < len(val_t.params) else Type("Any")
                                env[elt.id] = et
                    else:
                        for elt in target.elts:
                            if isinstance(elt, ast.Name):
                                env[elt.id] = Type("Any")
                elif isinstance(target, ast.Subscript):
                    check_expr(target.value)
                    check_expr(target.slice)
        elif isinstance(stmt, ast.AnnAssign):
            target = stmt.target.id if isinstance(stmt.target, ast.Name) else None
            declared = parse_type(stmt)
            if stmt.value:
                val_t = check_expr(stmt.value)
                if declared and declared.base != "Any" and val_t and val_t.base != "Any" and not is_subtype(val_t, declared):
                    typecheck_error(stmt, f"cannot assign '{val_t}' to variable '{target}' of type '{declared}'")
            if target and declared:
                env[target] = declared
                # 同时写入 TYPE_ENV，供代码生成阶段选择特化运算符/数组 accessor
                TYPE_ENV[target] = declared
        elif isinstance(stmt, ast.AugAssign):
            target_t = check_expr(stmt.target)
            val_t = check_expr(stmt.value)
            infer_binop(stmt.op, target_t, val_t)
        elif isinstance(stmt, ast.Return):
            val_t = check_expr(stmt.value)
            # 返回局部嵌套函数时，arrow[int,int] 应兼容 Callable[[int], int]
            if ret_type and val_t and not is_subtype(val_t, ret_type):
                # 对函数值做额外兼容：arrow[..., ret] <: Callable[..., ret]
                if not (val_t.base == "arrow" and ret_type.base in ("Callable", "arrow") and len(val_t.params) == len(ret_type.params)):
                    typecheck_error(stmt, f"return value of type '{val_t}' does not match declared return type '{ret_type}'")
        elif isinstance(stmt, ast.If):
            cond_t = check_expr(stmt.test)
            if cond_t and cond_t.base != "bool":
                typecheck_error(stmt, f"if condition must be bool, got '{cond_t}'")
            for s in stmt.body:
                check_stmt(s)
            for s in stmt.orelse:
                check_stmt(s)
        elif isinstance(stmt, ast.For):
            if isinstance(stmt.iter, ast.Call) and hasattr(stmt.iter.func, 'id') and stmt.iter.func.id == 'range':
                for arg in stmt.iter.args:
                    check_expr(arg)
                if isinstance(stmt.target, ast.Name):
                    env[stmt.target.id] = Type("int")
            else:
                iter_t = check_expr(stmt.iter)
                elem_t = None
                if iter_t and iter_t.base in ("list", "array") and iter_t.params:
                    elem_t = iter_t.params[0]
                elif iter_t and iter_t.base == "str":
                    elem_t = Type("str")
                if isinstance(stmt.target, ast.Name):
                    env[stmt.target.id] = elem_t or Type("Any")
            for s in stmt.body:
                check_stmt(s)
        elif isinstance(stmt, ast.While):
            cond_t = check_expr(stmt.test)
            if cond_t and cond_t.base != "bool":
                typecheck_error(stmt, f"while condition must be bool, got '{cond_t}'")
            for s in stmt.body:
                check_stmt(s)
        elif isinstance(stmt, ast.Expr):
            check_expr(stmt.value)
        elif isinstance(stmt, ast.FunctionDef):
            typecheck_function(stmt, function_arities, module_env)

    for s in node.body:
        check_stmt(s)


def collect_function_arities(tree):
    """收集所有顶层函数定义的参数数量"""
    arities = {}
    for node in tree.body:
        if isinstance(node, ast.FunctionDef):
            arities[node.name] = len(node.args.args)
    return arities


def typecheck_module(tree):
    """模块级类型检查入口"""
    # 先收集函数签名，让函数之间可以互相检查
    collect_function_signatures(tree)
    arities = collect_function_arities(tree)
    # 顶层变量类型环境（目前只有 enum 常量等）
    module_env = {}
    for node in tree.body:
        if isinstance(node, ast.ClassDef) and is_enum_class(node):
            for item in node.body:
                if isinstance(item, ast.Assign) and len(item.targets) == 1 and isinstance(item.targets[0], ast.Name):
                    module_env[f"{node.name}_{item.targets[0].id}"] = Type("int")
    for node in tree.body:
        if isinstance(node, ast.FunctionDef):
            typecheck_function(node, arities, module_env)


def debug_annotation(node, source_file=""):
    """生成源码行号注释，用于 Scheme 输出"""
    if node and hasattr(node, 'lineno'):
        fname = source_file or "<input>"
        return f";; {fname}:{node.lineno}"
    return ""

# =============================================================================
# 张量方法 / 属性翻译（transformers 风格 tensor 语法 → StaticPy 函数式调用）
#
# 参考实现（modeling_deepseekv2.py）写的是 x.to(dtype).pow(2).mean(-1, keepdim=True)
# 这类方法链，StaticPy 原本不支持。这里把 <expr>.method(args, **kw) 统一翻译成
# (torch-tensor-<method> <expr> 位置参数)，kw 按 TENSOR_METHOD_KW 表展开成位置参数。
# =============================================================================

# 允许的张量方法（只在已知集合内分派，避免劫持普通对象属性）
TENSOR_METHODS = {
    "to", "pow", "mean", "sum", "view", "reshape", "transpose", "permute",
    "unsqueeze", "squeeze", "split", "contiguous", "expand", "masked_fill",
    "gather", "index_select", "sqrt", "mul", "add", "sub", "div", "softmax", "argmax",
    "clone", "float", "detach", "max", "new_zeros", "repeat", "ne", "gt",
    "lt", "eq", "matmul", "reshape_as", "narrow", "neg", "permute", "cat", "div", "add", "mul",
    "unsqueeze", "squeeze", "transpose", "view", "mean", "sum",
}

# 方法关键字参数 → 最终位置参数下标（不含接收者）
# 例如 to(dtype=..) 的第 0 个位置参数是 dtype；mean(dim, keepdim) …
TENSOR_METHOD_KW = {
    "to":         {"dtype": 0, "device": 1},
    "mean":       {"dim": 0, "keepdim": 1},
    "sum":        {"dim": 0, "keepdim": 1},
    "softmax":    {"dim": 0},
    "max":        {"dim": 0, "keepdim": 1},
    "argmax":     {"dim": 0, "keepdim": 1},
    "masked_fill": {"mask": 0, "value": 1},
    "pow":        {},
    "transpose":  {},
    "permute":    {},
    "unsqueeze":  {},
    "squeeze":    {},
    "split":      {},
    "expand":     {},
    "view":       {},
    "reshape":    {},
    "matmul":     {},
    "sqrt":       {},
    "mul":        {},
    "add":        {},
    "clone":      {},
    "contiguous": {},
    "gather":     {},
    "index_select": {},
    "float":      {},
    "detach":     {},
    "ne":         {},
    "gt":         {},
    "lt":         {},
    "eq":         {},
    "repeat":     {},
    "narrow":     {},
    "reshape_as": {},
    "new_zeros":  {},
}

# torch.<dtype> 常量 → dtype 码（与 libtorch_std_helper dtype 枚举一致）
TORCH_DTYPE_CONST = {
    "float32": 0, "float64": 1, "int32": 2, "int64": 3,
    "float16": 5, "half": 5, "bfloat16": 6,
}

# tensor 无调用属性 → 运行时查询
TENSOR_ATTR_FN = {
    "dtype": "torch-tensor-dtype",
    "shape": "torch-tensor-shape",
    "T":     "torch-tensor-transpose-all",
    "ndim":  "torch-tensor-ndim",
}

# torch.<fn>(...) 返回张量的模块函数（用于二元运算的类型路由）
TENSOR_MODULE_FNS = {
    "rsqrt", "sqrt", "ones", "zeros", "empty", "tensor", "randn", "randint",
                    "matmul", "add", "mul", "sub", "cat", "stack", "softmax", "relu",
                    "sigmoid", "tanh", "clone", "reshape", "mean", "sum", "gather",
                    "argmax", "exp", "log", "abs", "where", "masked_fill", "to",
    "argmax", "exp", "log", "abs", "where", "masked_fill", "to",
    "expm1", "log1p", "full", "arange",
}

# 当前函数作用域内已知的张量变量（translate_function 预扫描后填充）
CURRENT_TENSOR_VARS = set()


def _tensor_module_call(node):
    """ast.Call 形如 torch.rsqrt(...) / 模块别名.fn(...) 且 fn 返回张量"""
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
        recv = node.func.value
        attr = node.func.attr
        if isinstance(recv, ast.Name) and is_module_alias(recv.id):
            # 排除非张量返回：available / to_list / numel 等
            if attr in TENSOR_MODULE_FNS:
                return True
    return False


def expr_is_tensor(node):
    """启发式：表达式是否为（或产生）张量。用于二元运算的类型路由。"""
    if node is None:
        return False
    if isinstance(node, ast.Call):
        if isinstance(node.func, ast.Attribute):
            if node.func.attr in TENSOR_METHODS:
                return True
        if _tensor_module_call(node):
            return True
    if isinstance(node, ast.Name):
        return node.id in CURRENT_TENSOR_VARS
    if isinstance(node, ast.Attribute):
        return node.attr in ("T",) or (isinstance(node.value, ast.Name) and node.value.id in CURRENT_TENSOR_VARS)
    if isinstance(node, ast.Subscript):
        # 张量 Ellipsis 切片结果 / 对张量的下标 → 张量
        if isinstance(node.slice, ast.Tuple) and len(node.slice.elts) == 2 and \
           isinstance(node.slice.elts[0], ast.Constant) and node.slice.elts[0].value is Ellipsis:
            return True
        return expr_is_tensor(node.value)
    if isinstance(node, ast.BinOp):
        # 张量二元运算结果仍是张量（任一侧是张量）
        return expr_is_tensor(node.left) or expr_is_tensor(node.right)
    if isinstance(node, ast.Call):
        return expr_is_tensor(node.func) if isinstance(node.func, ast.Call) else False
    return False


def scan_tensor_vars(stmts):
    """扫描函数体，收集被赋值为张量表达式的变量名"""
    out = set()
    def rec(nodes):
        for s in nodes:
            if isinstance(s, ast.Assign):
                if len(s.targets) == 1 and isinstance(s.targets[0], ast.Name):
                    if expr_is_tensor(s.value):
                        out.add(s.targets[0].id)
            elif isinstance(s, ast.AnnAssign) and isinstance(s.target, ast.Name) and s.value:
                if expr_is_tensor(s.value):
                    out.add(s.target.id)
            elif isinstance(s, ast.AugAssign) and isinstance(s.target, ast.Name):
                if expr_is_tensor(s.value):
                    out.add(s.target.id)
            elif isinstance(s, ast.If):
                rec(s.body); rec(s.orelse)
            elif isinstance(s, ast.For):
                rec(s.body)
            elif isinstance(s, ast.While):
                rec(s.body)
            elif isinstance(s, ast.With):
                for w in s.items:
                    if w.body: rec(w.body)
    rec(stmts)
    return out


def tensor_dtype_code(node):
    """torch.float32 / torch.bfloat16 等常量 → dtype 码"""
    if isinstance(node, ast.Attribute) and isinstance(node.value, ast.Name):
        if is_module_alias(node.value.id):
            scheme_fn = resolve_module_function(node.value.id, node.value.attr)
            if scheme_fn == "torch-available":
                return None
        # torch.float32 / np.float32 字面常量
        if node.attr in TORCH_DTYPE_CONST:
            return TORCH_DTYPE_CONST[node.attr]
    return None


def translate_tensor_method(receiver, attr, node):
    """把 <receiver>.<attr>(args, **kwargs) 翻译为 (torch-tensor-<attr> ...)。
    返回 None 表示不是（可识别的）张量方法调用。"""
    if attr not in TENSOR_METHODS:
        return None
    # 位置参数（转 dtype 常量 / 常规表达式）
    pos = []
    for a in node.args:
        dc = tensor_dtype_code(a)
        if dc is not None:
            pos.append(str(dc))
        else:
            pos.append(translate_expr(a))
    # 关键字参数 → 按表展开到最终位置
    if node.keywords:
        kw = TENSOR_METHOD_KW.get(attr, {})
        # 先算已有位置参数个数，kwarg 必须落在后续空位
        kwargs = {}
        for k in node.keywords:
            if k.arg is None:
                continue
            if k.arg not in kw:
                continue
            v = k.value
            dc = tensor_dtype_code(v)
            if dc is not None:
                kwargs[kw[k.arg]] = str(dc)
            elif isinstance(v, ast.Constant) and isinstance(v.value, bool):
                # FFI int 位用 0/1（不能 #t）
                kwargs[kw[k.arg]] = "1" if v.value else "0"
            else:
                kwargs[kw[k.arg]] = translate_expr(v)
        # 合并：位置参数先占 [0, n)，kwarg 填剩余位置（保证不重叠）
        npos = len(pos)
        merged = pos[:]
        for idx in sorted(kwargs):
            while len(merged) <= idx:
                merged.append("#f")
            merged[idx] = kwargs[idx]
        pos = merged
    return f"(torch-tensor-{attr} {receiver} {' '.join(pos)})"



def translate_expr(node):
    """翻译一个表达式"""
    if node is None:
        return "#f"
    if isinstance(node, ast.Constant):
        if node.value is True:
            return "#t"
        if node.value is False:
            return "#f"
        if node.value is None:
            return "#f"
        if isinstance(node.value, str):
            s = node.value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t").replace("\r", "\\r")
            return f'"{s}"'
        return repr(node.value)
    if isinstance(node, ast.Name):
        # 优先处理 from ... import 导入的裸函数名
        module, scheme_fn = resolve_imported_name(node.id)
        if scheme_fn:
            return scheme_fn
        return mangle_name(node.id)
    elif isinstance(node, ast.UnaryOp):
        if isinstance(node.op, ast.Not):
            return f"(not {translate_expr(node.operand)})"
        if isinstance(node.op, ast.USub):
            # 张量取负 → torch-tensor-neg
            if expr_is_tensor(node.operand):
                return f"(torch-tensor-neg {translate_expr(node.operand)})"
            return f"(- {translate_expr(node.operand)})"
        return f"({type(node.op).__name__} {translate_expr(node.operand)})"
    elif isinstance(node, ast.BinOp):
        if isinstance(node.op, ast.Add):
            lt = infer_expr_type(node.left)
            rt = infer_expr_type(node.right)
            if (lt and str(lt).startswith("list")) or (rt and str(rt).startswith("list")):
                return translate_binop("Add", node.left, node.right)
        return translate_binop(type(node.op).__name__, node.left, node.right)
    elif isinstance(node, ast.Compare):
        if len(node.ops) == 1 and len(node.comparators) == 1:
            return translate_compare(node.ops[0], node.left, node.comparators[0])
        return f"(and {translate_expr(node.left)} ... cmp)"
    elif isinstance(node, ast.Call):
        func = node.func
        args = [translate_expr(a) for a in node.args]
        if isinstance(func, ast.Name):
            name = func.id
            # Option/Result/Some constructors
            if name in ("Ok", "Error", "Some"):
                if len(args) != 1:
                    return gen_error(node, f"{name} expects exactly 1 argument")
                return f"({name} {' '.join(args)})"
            # none() constructor
            if name == "none":
                return "(None)"
            # Dataclass constructors: Point(1.0, 2.0) -> (make-Point 1.0 2.0)
            if name in RECORD_TYPES:
                return f"(make-{name} {' '.join(args)})"
            # 处理 from ... import 导入的裸函数名
            module, scheme_fn = resolve_imported_name(name)
            if scheme_fn == "np-array":
                # from np import array 后的 array([...])
                if node.args and isinstance(node.args[0], ast.List):
                    inner = " ".join(translate_expr(e) for e in node.args[0].elts)
                    return f"(np-array (vector {inner}) {len(node.args[0].elts)})"
                return f"(np-array {' '.join(args)})"
            if scheme_fn:
                return f"({scheme_fn} {' '.join(args)})"
            # Pythonic from import: from math import sin
            if name in MATH_FUNCTIONS:
                return f"({name} {' '.join(args)})"
            # 外部 FFI 函数
            if name in EXTERN_FUNCTIONS:
                ffi = EXTERN_FUNCTIONS[name]
                return f"({name} {' '.join(args)})"
            # 内置函数
            if name in ("len",):
                if args:
                    return f"(list_length {args[0]})"
                return "0"
            # Python isinstance(expr, EConst) -> (ir-tag? expr 'EConst)
            if name == "isinstance":
                if len(args) == 2:
                    return f"(ir-tag? {args[0]} '{args[1]})"
                return gen_error(node, "isinstance expects 2 arguments")
            if name == "print":
                return f"(print {' '.join(args)})"
            if name == "exit":
                return f"(exit_program {' '.join(args)})"
            if name == "range":
                return f"({args[0]})"  # simplified
            if name == "int":
                return f"(exact (round {args[0]}))" if args else "0"
            if name == "float":
                return f"(inexact {args[0]})" if args else "0.0"
            if name == "bool":
                return f"(not (not {args[0]}))" if args else "#f"
            if name == "abs":
                return f"(abs {args[0]})" if args else "0"
            if name == "pow":
                return f"(pow {args[0]} {args[1]})" if len(args) >= 2 else "1"
            if name == "none":
                return "(None)"
            # Option/Result helper functions
            if name in ("is_ok", "is_error", "is_some", "is_none", "unwrap", "unwrap_or", "unwrap_error"):
                return f"({name} {' '.join(args)})"
            # 预置函数（Scheme 运行时，不走 FFI，无需 extern fn 声明）
            if name in PRELUDE_FUNCTIONS:
                return f"({scheme_name(name)} {' '.join(args)})"
            # IR / dataclass-style class constructors: EConst(x) -> (vector 'EConst x)
            if name in RECORD_TYPES or name in ("EConst", "EVar", "EBinop", "EUnary", "ECall", "SLet", "SSet", "SReturn", "SExpr", "SIf", "SWhile", "SFor", "IRFunc"):
                return f"(vector '{name} {' '.join(args)})"
            # 参数可能是函数值（高阶函数），不加 static_ 前缀
            if isinstance(node, ast.FunctionDef):
                arg_names = [arg.arg for arg in node.args.args]
            elif isinstance(node, ast.Lambda):
                arg_names = [arg.arg for arg in node.args.args]
            else:
                arg_names = []
            arg_idx = arg_names.index(name) if name in arg_names else -1
            if arg_idx >= 0:
                return f"({mangle_name(name)} {' '.join(args)})"
            # 局部变量可能是函数值（高阶函数），不加 static_ 前缀
            if name in TYPE_ENV:
                return f"({mangle_name(name)} {' '.join(args)})"
            # 用户自定义函数加 static_ 前缀
            return f"(static_{name} {' '.join(args)})"
        elif isinstance(func, ast.Attribute):
            # np.dot / torch.matmul / la.svd 等
            obj = None
            attr = func.attr
            value = translate_expr(func.value)
            if isinstance(func.value, ast.Name):
                obj = func.value.id
            if isinstance(func.value, ast.Attribute):
                obj = translate_expr(func.value)
            if obj:
                # 优先处理模块别名：np.array / torch.add 等
                if is_module_alias(obj):
                    scheme_fn = resolve_module_function(obj, attr)
                    if scheme_fn == "np-array":
                        # np.array([...]) 直接生成 tagged array（不重复包装内部 list）
                        if node.args and isinstance(node.args[0], ast.List):
                            inner = " ".join(translate_expr(e) for e in node.args[0].elts)
                            return f"(np-array (vector {inner}) {len(node.args[0].elts)})"
                        return f"(np-array {' '.join(args)})"
                    if scheme_fn:
                        # 追加关键字实参（按出现顺序排在位置参数后），如 torch.cat(ts, dim=-1)
                        extra = [translate_expr(k.value) for k in node.keywords if k.arg is not None]
                        all_args = args + extra
                        return f"({scheme_fn} {' '.join(all_args)})"
                # 处理嵌套模块别名：os.path.exists
                if isinstance(func.value, ast.Attribute) and isinstance(func.value.value, ast.Name):
                    top = func.value.value.id
                    mid = func.value.attr
                    if is_module_alias(top):
                        scheme_fn = resolve_nested_module((top, mid), attr)
                        if scheme_fn:
                            return f"({scheme_fn} {' '.join(args)})"
                # numpy 兼容（无 import 也兼容裸 np.）
                if obj == "np":
                    NUMPY_MAP = {
                        "array": "np-array",
                        "dot": "np-dot", "daxpy": "np-daxpy",
                        "copy": "np-copy", "scal": "np-scal",
                        "gemv": "np-gemv", "gemm": "np-gemm",
                        "matmul": "np-gemm",
                        "sum": "np-sum", "mean": "np-mean",
                        "max": "np-max", "min": "np-min",
                        "zeros": "np-zeros", "ones": "np-ones",
                        "sqrt": "np-sqrt", "exp": "np-exp",
                        "abs": "np-abs", "argmax": "np-argmax",
                        "arange": "np-arange", "linspace": "np-linspace",
                        "concatenate": "np-concatenate", "clip": "np-clip",
                    }
                    mapped = NUMPY_MAP.get(attr, attr)
                    return f"({mapped} {' '.join(args)})"
            # Pythonic 模块兼容（无 import 也兼容裸 math.sin 等）
            if obj == "math":
                MATH_MAP = {
                    "sin": "sin", "cos": "cos", "tan": "tan",
                    "log": "log", "log2": "log2", "log10": "log10", "exp": "exp",
                    "sqrt": "sqrt", "abs": "abs", "pow": "pow", "fmod": "fmod",
                    "floor": "floor", "ceil": "ceil", "round": "round",
                    "sinh": "sinh", "cosh": "cosh", "tanh": "tanh",
                    "atan2": "atan2", "asin": "asin", "acos": "acos", "atan": "atan",
                    "pi": "pi", "e": "e",
                }
                mapped = MATH_MAP.get(attr, attr)
                return f"({mapped} {' '.join(args)})"
            # dict.copy() / list.copy() 等无参方法
            if attr == "copy":
                return f"(dict-copy {value})"
            if obj == "random":
                RANDOM_MAP = {
                    "seed": "random_seed",
                    "random": "random_float",
                    "randint": "random_randint",
                    "uniform": "random_uniform",
                    "choice": "random_choice",
                }
                mapped = RANDOM_MAP.get(attr, attr)
                return f"({mapped} {' '.join(args)})"
            if obj == "json":
                JSON_MAP = {
                    "loads": "parse_json",
                    "dumps": "json_dumps",
                }
                mapped = JSON_MAP.get(attr, attr)
                return f"({mapped} {' '.join(args)})"
            if obj == "time":
                TIME_MAP = {
                    "time": "clock",
                    "sleep": "sleep",
                    "strftime": "format_time",
                }
                mapped = TIME_MAP.get(attr, attr)
                return f"({mapped} {' '.join(args)})"
            if obj == "os":
                OS_MAP = {
                    "listdir": "os_list_dir",
                    "mkdir": "os_mkdir",
                    "rmdir": "os_rmdir",
                    "getenv": "os_getenv",
                    "getcwd": "os_cwd",
                    "rename": "os_move_file",
                    "remove": "os_delete_file",
                    "system": "os_shell",
                }
                mapped = OS_MAP.get(attr, attr)
                if mapped:
                    return f"({mapped} {' '.join(args)})"
                # os.path.xxx
                if attr == "path" and node.args:
                    pass
            # os.path.xxx
            if obj == "os.path" or (isinstance(func.value, ast.Attribute) and isinstance(func.value.value, ast.Name) and func.value.value.id == "os" and func.value.attr == "path"):
                OS_PATH_MAP = {
                    "exists": "os_file_exists",
                    "getsize": "os_file_size",
                }
                mapped = OS_PATH_MAP.get(attr, attr)
                return f"({mapped} {' '.join(args)})"
            # urllib.request.urlopen
            if obj == "urllib.request" or (isinstance(func.value, ast.Attribute) and isinstance(func.value.value, ast.Name) and func.value.value.id == "urllib" and func.value.attr == "request"):
                if attr == "urlopen":
                    return f"(http_get_simple {' '.join(args)})"
            # cuda 兼容
            if obj == "cuda":
                CUDA_MAP = {
                    "gemm": "cuda-gemm",
                }
                mapped = CUDA_MAP.get(attr, attr)
                return f"({mapped} {' '.join(args)})"
            # scipy.linalg 兼容
            if obj == "la":
                LA_MAP = {
                    "solve": "la-solve", "svd": "la-svd",
                    "eigvals": "la-eigvals",
                }
                mapped = LA_MAP.get(attr, attr)
                return f"({mapped} {' '.join(args)})"
            # PyTorch 兼容
            if obj == "torch":
                TORCH_MAP = {
                    "tensor": "torch-tensor",
                    "empty": "torch-empty",
                    "zeros": "torch-zeros",
                    "ones": "torch-ones",
                    "add": "torch-add", "mul": "torch-mul",
                    "sub": "torch-sub", "matmul": "torch-matmul",
                    "cat": "torch-cat", "neg": "torch-tensor-neg", "topk": "torch-topk", "tpack_load": "torch-tpack-load", "tpack_get": "torch-tpack-get", "tpack_index": "torch-tpack-index", "tensor_ptr": "torch-tensor-ptr-debug", "cos": "torch-cos", "sin": "torch-sin", "outer": "torch-outer", "rope_inv_freq": "torch-rope-inv-freq", "rope_t": "torch-rope-t", "rope_t_pos": "torch-rope-t-pos", "causal_mask": "torch-causal-mask", "cat_id": "torch-cat-id", "last_argmax": "torch-last-argmax", "narrow": "torch-narrow",
                    "neg": "torch-tensor-neg", "rsqrt": "torch-rsqrt",
                    "sqrt": "torch-sqrt", "softmax": "torch-softmax",
                    "index_select": "torch-tensor-index-select",
                    "clone": "torch-clone", "reshape": "torch-reshape",
                    "to_list": "torch-to-list",
                    "available": "torch-available",
                    "rsqrt": "torch-rsqrt",
                    "sqrt": "torch-sqrt",
                    "conv2d": "torch-conv2d",
                    # SD / JIT / DDPM extensions
                    "sd_unet_forward": "torch-sd-unet-forward",
                    "load_image": "torch-load-image",
                    "save_image": "torch-save-image",
                    "ddpm_betas": "torch-ddpm-betas",
                    "ddpm_add_noise": "torch-ddpm-add-noise",
                    "jit_load": "torch-jit-load",
                    "jit_forward": "torch-jit-forward",
                    "jit_delete": "torch-jit-delete",
                    "save_state_dict": "torch-save-state-dict",
                    # CLIP tokenizer
                    "clip_tokenizer_create": "torch-clip-tokenizer-create",
                    "clip_tokenizer_encode": "torch-clip-tokenizer-encode",
                    "clip_tokenizer_free": "torch-clip-tokenizer-free",
                    # CLIP text encoder
                    "clip_text_forward": "torch-clip-text-forward",
                    # safetensors
                    "safetensors_load": "torch-safetensors-load",
                    "safetensors_count": "torch-safetensors-count",
                    "safetensors_name": "torch-safetensors-name",
                    "safetensors_tensor": "torch-safetensors-tensor",
                    "safetensors_free": "torch-safetensors-free",
                    "safetensors_get_tensor_by_name": "torch-safetensors-get-tensor-by-name",
                    # LoRA
                    "lora_apply": "torch-lora-apply",
                    "lora_merge_into": "torch-lora-merge-into",
                    # Samplers
                    "sample_ddim": "torch-sample-ddim",
                    "sample_euler": "torch-sample-euler",
                    "sample_euler_ancestral": "torch-sample-euler-ancestral",
                    "sample_dpmpp_2m": "torch-sample-dpmpp-2m",
                    "sampler_sigmas": "torch-sampler-sigmas",
                    # Image processing
                    "image_resize": "torch-image-resize", "image_resize_float": "torch-image-resize-float",
                    "image_crop": "torch-image-crop",
                    "image_composite": "torch-image-composite",
                    "color_convert": "torch-color-convert",
                    # ControlNet
                    "controlnet_forward": "torch-controlnet-forward",
                    "controlnet_apply": "torch-controlnet-apply",
                    # VAE tiling
                    "vae_encode_tiled": "torch-vae-encode-tiled",
                    "vae_decode_tiled": "torch-vae-decode-tiled",
                    # GGUF
                    "gguf_load": "torch-gguf-load",
                    "gguf_tensor_count": "torch-gguf-tensor-count",
                    "gguf_tensor_name": "torch-gguf-tensor-name",
                    "gguf_load_tensor": "torch-gguf-load-tensor",
                    "gguf_load_tensor_by_name": "torch-gguf-load-tensor-by-name",
                    "gguf_free": "torch-gguf-free",
                    # SDXL
                    "sdxl_unet_forward": "torch-sdxl-unet-forward",
                    "sdxl_dual_clip": "torch-sdxl-dual-clip",
                    # T5
                    "t5_tokenizer_create": "torch-t5-tokenizer-create",
                    "t5_tokenizer_encode": "torch-t5-tokenizer-encode",
                    "t5_tokenizer_free": "torch-t5-tokenizer-free",
                    # FLUX
                    "flux_forward": "torch-flux-forward",
                    # Flow Matching
                    "fm_sigmas": "torch-fm-sigmas",
                    "fm_step": "torch-fm-step",
                    "randint": "torch-randint",
                }
                mapped = TORCH_MAP.get(attr, attr)
                return f"({mapped} {' '.join(args)})"
            # ML Runtime: 所有 ML 库的统一入口
            if obj == "ml":
                return f"(ml_{attr} {' '.join(args)})"

            # 张量方法调用：<tensor>.method(args, **kwargs) → (torch-tensor-<method> <tensor> 位置参数)
            # 用于把 transformers 风格代码（x.to(dtype), x.pow(2).mean(-1, keepdim=True)）忠实翻译。
            if not is_module_alias(obj):
                t = translate_tensor_method(value, attr, node)
                if t:
                    return t
            # 普通属性访问（未知对象）：content.splitlines → content-splitlines
            return f"({value}-{attr})"
        # 接收者是表达式（如嵌套调用/下标），非模块名 → 同样尝试张量方法
        if isinstance(func.value, ast.Attribute) or isinstance(func.value, ast.Subscript) or isinstance(func.value, ast.Call):
            t = translate_tensor_method(value, attr, node)
            if t:
                return t
        return f"({ast.dump(func)} {' '.join(args)})"
    elif isinstance(node, ast.Dict):
        # {"a": 1, "b": 2} → dict literal
        keys = [translate_expr(k) for k in node.keys]
        vals = [translate_expr(v) for v in node.values]
        if not keys:
            return "(make-dict)"
        # Build dict by sequential set! in the caller
        # Return a make-dict + series of dict-set! as a single expression
        items = []
        for k, v in zip(keys, vals):
            items.append(f"(dict-set! d {k} {v})")
        return f"(let ((d (make-dict))) {' '.join(items)} d)"
    elif isinstance(node, ast.Tuple):
        # Tuple 表达式：转成 vector
        elems = [translate_expr(e) for e in node.elts]
        return f"(vector {' '.join(elems)})"
    elif isinstance(node, ast.List):
        elems = [translate_expr(e) for e in node.elts]
        n = len(elems)
        return f"(py-list {' '.join(elems)})"
    elif isinstance(node, ast.ListComp):
        # 简化: [expr for i in range(n)] → (py-list ... loop)
        if len(node.generators) == 1:
            gen = node.generators[0]
            target = mangle_name(gen.target.id) if isinstance(gen.target, ast.Name) else "i"
            if isinstance(gen.iter, ast.Call) and hasattr(gen.iter.func, 'id') and gen.iter.func.id == 'range':
                rargs = gen.iter.args
                if len(rargs) == 1:
                    n = translate_expr(rargs[0])
                    body = translate_expr(node.elt)
                    return f"(list->py-list (let loop (({target} 0) (acc '())) (if (>= {target} {n}) (reverse acc) (loop (+ {target} 1) (cons {body} acc)))))"
        return "(py-list)"
    elif isinstance(node, ast.Set):
        # {1, 2, 3} → 转为 list（ Scheme 无 set，用 list 近似）
        elems = [translate_expr(e) for e in node.elts]
        return f"(py-list {' '.join(elems)})"
    elif isinstance(node, ast.GeneratorExp):
        # 同 ListComp 简化处理
        if len(node.generators) == 1:
            gen = node.generators[0]
            target = mangle_name(gen.target.id) if isinstance(gen.target, ast.Name) else "i"
            if isinstance(gen.iter, ast.Call) and hasattr(gen.iter.func, 'id') and gen.iter.func.id == 'range':
                rargs = gen.iter.args
                if len(rargs) == 1:
                    n = translate_expr(rargs[0])
                    body = translate_expr(node.elt)
                    return f"(list->vector (let loop (({target} 0) (acc '())) (if (>= {target} {n}) (reverse acc) (loop (+ {target} 1) (cons {body} acc)))))"
        return "(vector)"
    elif isinstance(node, ast.Subscript):
        # a[i] / a[i:j] / a[i:j:k] → 根据 value 类型选择 accessor 或 slice
        value = translate_expr(node.value)
        slc = node.slice
        vt = infer_expr_type(node.value)
        # x[..., :k] / x[..., k:]（Ellipsis + 单段切片）→ 沿最后一维切片（恒为张量语义）
        if isinstance(slc, ast.Tuple) and len(slc.elts) == 2:
            if isinstance(slc.elts[0], ast.Constant) and slc.elts[0].value is Ellipsis and isinstance(slc.elts[1], ast.Slice):
                s = slc.elts[1]
                lo = translate_expr(s.lower) if s.lower else "0"
                up = translate_expr(s.upper) if s.upper else "-1"
                return f"(torch-tensor-slice-last {value} {lo} {up})"
        # <tensor>.shape[i] / <vec>[i]：shape 查询返回 Scheme vector → vector-ref
        if isinstance(node.value, ast.Attribute) and node.value.attr in ("shape", "dims"):
            # 负索引：.shape[-1] → (vector-ref v (fx- (vector-length v) 1))
            if isinstance(slc, ast.UnaryOp) and isinstance(slc.op, ast.USub) and isinstance(slc.operand, ast.Constant):
                return f"(vector-ref {value} (fx- (vector-length {value}) {slc.operand.value}))"
            idx = translate_expr(slc)
            return f"(vector-ref {value} {idx})"
        # 张量特殊语法
        if expr_is_tensor(node.value):
            # x[pos_ids] / x[i]（tensor 索引）→ 沿 dim0 index_select
            if not isinstance(slc, (ast.Slice, ast.Tuple)):
                idx = translate_expr(slc)
                return f"(torch-tensor-index-select {value} {idx})"
        # 切片
        if isinstance(slc, ast.Slice):
            start = translate_expr(slc.lower) if slc.lower else "0"
            end_expr = slc.upper
            if end_expr is None:
                if vt == "str":
                    end = f"(string-length {value})"
                elif vt and str(vt).startswith("list["):
                    end = f"(tagged-array-len {value})"
                else:
                    end = f"(vector-length {value})"
            else:
                end = translate_expr(end_expr)
            if vt == "str":
                return f"(slice-string {value} {start} {end})"
            if vt and str(vt).startswith("list["):
                return f"(make-tagged-array (slice-array (tagged-array-data {value}) {start} {end}) (- {end} {start}))"
            # fallback: runtime dispatch between string and vector/array slices
            return f"(if (string? {value}) (slice-string {value} {start} {end}) (slice-array {value} {start} {end}))"
        # 索引
        idx = translate_expr(slc)
        # If the index is a string literal, use dict-get
        if isinstance(slc, ast.Constant) and isinstance(slc.value, str):
            return f"(dict-get {value} {idx})"
        if vt == "list[float]":
            return f"(float_array_ref {value} {idx})"
        if vt == "tuple":
            return f"(vector-ref {value} {idx})"
        if vt == "list":
            return f"(py-list-ref {value} {idx})"
        if vt and str(vt).startswith("vector["):
            return f"(vector-ref {value} {idx})"
        if vt and str(vt).startswith("list["):
            return f"(vector-ref {value} {idx})"
        if vt == "str":
            return f"(slice-string {value} {idx} (fx+ {idx} 1))"
        return f"(vector-ref {value} {idx})"
    elif isinstance(node, ast.Attribute):
        # torch.float32 / torch.bfloat16 等 dtype 常量 → dtype 码
        if isinstance(node.value, ast.Name) and is_module_alias(node.value.id) and node.attr in TORCH_DTYPE_CONST:
            return str(TORCH_DTYPE_CONST[node.attr])
        # 张量属性：<tensor>.dtype / .shape / .ndim / .T → 运行时查询函数
        if node.attr in TENSOR_ATTR_FN:
            return f"({TENSOR_ATTR_FN[node.attr]} {translate_expr(node.value)})"
        if isinstance(node.value, ast.Name) and node.attr == "append":
            return f"(py-list-append {mangle_name(node.value.id)}"
        # list.length -> (py-list-length lst)
        if isinstance(node.value, ast.Name) and node.attr == "length":
            return f"(py-list-length {mangle_name(node.value.id)})"
        if node.attr == "ref" or node.attr == "__getitem__":
            return f"(py-list-ref {mangle_name(node.value.id)}"
        # isinstance(expr, EConst) -> (ir-tag? expr 'EConst)
        if node.attr == "isinstance":
            return f"(ir-tag? {mangle_name(node.value.id)}"
        # 记录字段访问：p.x -> (Point-x p)，若知道 p 的类型
        if isinstance(node.value, ast.Name):
            vtype = TYPE_ENV.get(node.value.id)
            if vtype in RECORD_TYPES and node.attr in RECORD_TYPES[vtype]:
                return f"({vtype}-{node.attr} {node.value.id})"
        value = translate_expr(node.value)
        # dict.copy() -> (dict-copy dict)
        if node.attr == "copy":
            return f"(dict-copy {value})"
        # IR node field access: expr.value -> (ir-field expr 'value)
        # IR classes are plain Python classes translated to tagged vectors;
        # the same field name can live at different indices depending on the
        # node type, so use the runtime dispatcher `ir-field`.
        IR_FIELDS = {
            "value", "name", "operand", "func", "args",
            "cond_expr", "then_body", "else_body",
            "var", "stop", "body",
            "params", "param_types", "ret",
            "op", "left", "right",
            "ty",
        }
        if node.attr in IR_FIELDS:
            return f"(ir-field {value} '{node.attr})"
        return f"({node.attr} {value})"
    elif isinstance(node, ast.JoinedStr):
        # f-string: f"hello {name}" → (string-append "hello " (format "~s" name))
        parts = []
        for val in node.values:
            if isinstance(val, ast.Constant):
                parts.append(translate_expr(val))
            elif isinstance(val, ast.FormattedValue):
                # {expr} → (format "~s" expr)
                expr = translate_expr(val.value)
                parts.append(f"(format \"~a\" {expr})")
            else:
                parts.append('""')
        if len(parts) == 1:
            return parts[0]
        return "(string-append " + " ".join(parts) + ")"
    elif isinstance(node, ast.IfExp):
        test = translate_expr(node.test)
        body = translate_expr(node.body)
        orelse = translate_expr(node.orelse)
        return f"(if {test} {body} {orelse})"
    elif isinstance(node, ast.BoolOp):
        # a and b and c, a or b or c
        op = "and" if isinstance(node.op, ast.And) else "or"
        vals = [translate_expr(v) for v in node.values]
        return f"({op} {' '.join(vals)})"
    elif isinstance(node, ast.NamedExpr):
        return translate_expr(node.value)
    elif isinstance(node, ast.Starred):
        return translate_expr(node.value)
    else:
        return f"(void)"


def translate_function(node, source_file=""):
    """翻译函数定义"""
    global TYPE_ENV
    # 每个函数独立的类型环境，避免嵌套函数污染
    saved_env = TYPE_ENV.copy()
    collect_function_types(node)

    # 张量变量作用域：预扫描本函数赋值，供二元运算路由
    global CURRENT_TENSOR_VARS
    saved_tensor_vars = CURRENT_TENSOR_VARS
    CURRENT_TENSOR_VARS = scan_tensor_vars(node.body)

    name = f"static_{node.name}"
    args = [mangle_name(arg.arg) for arg in node.args.args]

    # 收集本层局部定义的函数名，供返回/引用时加前缀
    LOCAL_FUNCTIONS = {stmt.name for stmt in node.body if isinstance(stmt, ast.FunctionDef)}

    all_bindings = []
    body_exprs = []
    si = 0
    lineno = getattr(node, 'lineno', 0)
    # Source line mapping header
    comment = f";; {source_file}:{lineno} def {node.name}()"
    
    while si < len(node.body):
        stmt = node.body[si]
        if isinstance(stmt, ast.ClassDef):
            body_exprs.append(translate_class(stmt))
        elif isinstance(stmt, ast.FunctionDef):
            body_exprs.append(translate_function(stmt, source_file))
        elif isinstance(stmt, ast.Return):
            val = translate_expr(stmt.value) if stmt.value else "#f"
            # 返回局部定义的嵌套函数名时，需要加上 static_ 前缀
            if stmt.value and isinstance(stmt.value, ast.Name) and stmt.value.id in LOCAL_FUNCTIONS:
                val = f"static_{stmt.value.id}"
            body_exprs.append(f"(__return__ {val})")
        elif isinstance(stmt, ast.AugAssign):
            body_exprs.append(translate_aug_assign(stmt))
        elif isinstance(stmt, (ast.Assign, ast.AnnAssign)):
            target = None
            val = None
            if isinstance(stmt, ast.AnnAssign):
                target = mangle_name(stmt.target.id) if isinstance(stmt.target, ast.Name) else None
                val = translate_expr(stmt.value) if stmt.value else "#f"
            else:
                if len(stmt.targets) == 1:
                    t = stmt.targets[0]
                    if isinstance(t, ast.Name):
                        target = t.id
                        val = translate_expr(stmt.value)
                    elif isinstance(t, ast.Tuple):
                        # 元组解构：a, b = expr → (let ((tmp expr)) (set! a (vector-ref tmp 0)) ...)
                        tmp = "__tmp_" + str(si)
                        tmp_val = translate_expr(stmt.value)
                        # 如果右侧是元组字面量，先转成 vector
                        if isinstance(stmt.value, ast.Tuple):
                            elems = [translate_expr(e) for e in stmt.value.elts]
                            tmp_val = f"(vector {' '.join(elems)})"
                        binds = []
                        for idx, elt in enumerate(t.elts):
                            if isinstance(elt, ast.Name):
                                binds.append(f"(set! {mangle_name(elt.id)} (vector-ref {tmp} {idx}))")
                        destructure = f"(let (({tmp} {tmp_val})) {' '.join(binds)})"
                        body_exprs.append(destructure)
                        # 元组解构已处理，跳过后续 set!
                        target = "__destructured__"
                        val = "#t"
                    elif isinstance(t, ast.Subscript):
                        d = translate_expr(t.value)
                        k = translate_expr(t.slice)
                        v = translate_expr(stmt.value)
                        body_exprs.append(f"(dict-set! {d} {k} {v})")
            if target and val and target != "__destructured__":
                # 从右侧表达式推断目标变量类型，仅用于辅助代码生成（如 subscript 选择 accessor）
                inferred = infer_expr_type(stmt.value)
                if inferred:
                    TYPE_ENV[mangle_name(target)] = inferred
                # 根据目标变量类型选择数组创建方式
                target_type = TYPE_ENV.get(mangle_name(target))
                if target_type == "list[float]" and isinstance(stmt.value, ast.Call):
                    # make_float_array 直接保留
                    body_exprs.append(f"(set! {target} {val})")
                elif target_type and str(target_type).startswith("list[") and isinstance(stmt.value, ast.List):
                    # list literal already (vector ...)
                    body_exprs.append(f"(set! {target} {val})")
                elif target_type and str(target_type).startswith("list[") and isinstance(stmt.value, ast.Call) and hasattr(stmt.value.func, 'id') and stmt.value.func.id == 'make_array':
                    body_exprs.append(f"(set! {target} {val})")
                else:
                    body_exprs.append(f"(set! {target} {val})")
            elif target != "__destructured__" and not (isinstance(stmt, ast.Assign) and len(stmt.targets) == 1 and isinstance(stmt.targets[0], ast.Subscript)):
                body_exprs.append(f";; {ast.dump(stmt)}")
        elif isinstance(stmt, ast.If):
            test = translate_expr(stmt.test)
            then_exprs = translate_block(stmt.body)
            else_body = stmt.orelse
            
            if else_body:
                else_exprs = translate_block(else_body)
                body_exprs.append(f"(if {test}\n    (begin {' '.join(then_exprs)})\n    (begin {' '.join(else_exprs)}))")
            elif (si + 1 < len(node.body) and isinstance(node.body[si + 1], ast.Return)
                  and len(stmt.body) > 0 and isinstance(stmt.body[-1], ast.Return)):
                # 优化: if cond: return a\nreturn b  →  (if cond a b)
                # 仅在 if 体也以 return 结尾时优化，否则 return 是公共尾路径
                next_stmt = node.body[si + 1]
                next_val = translate_expr(next_stmt.value) if next_stmt.value else "#f"
                body_exprs.append(f"(if {test}\n    (begin {' '.join(then_exprs)})\n    {next_val})")
                si += 1  # 跳过下一个 return
            else:
                body_exprs.append(f"(if {test}\n    (begin {' '.join(then_exprs)}))")
        elif isinstance(stmt, ast.For):
            target = mangle_name(stmt.target.id) if isinstance(stmt.target, ast.Name) else "i"
            if isinstance(stmt.iter, ast.Call) and hasattr(stmt.iter.func, 'id') and stmt.iter.func.id == 'range':
                rargs = stmt.iter.args
                if len(rargs) == 1:
                    n = translate_expr(rargs[0])
                    body_parts = translate_block(stmt.body)
                    body_str = " ".join(body_parts)
                    body_exprs.append(f"(do (({target} 0 (+ {target} 1))) ((>= {target} {n})) {body_str})")
                elif len(rargs) == 2:
                    start = translate_expr(rargs[0])
                    end = translate_expr(rargs[1])
                    body_parts = translate_block(stmt.body)
                    body_str = " ".join(body_parts)
                    body_exprs.append(f"(do (({target} {start} (+ {target} 1))) ((>= {target} {end})) {body_str})")
                elif len(rargs) == 3:
                    start = translate_expr(rargs[0])
                    end = translate_expr(rargs[1])
                    step = translate_expr(rargs[2])
                    body_parts = translate_block(stmt.body)
                    body_str = " ".join(body_parts)
                    body_exprs.append(f"(do (({target} {start} (+ {target} {step}))) ((>= {target} {end})) {body_str})")
                else:
                    body_exprs.append(f";; for range with {len(rargs)} args")
            elif isinstance(stmt.iter, ast.List) or isinstance(stmt.iter, ast.ListComp):
                # for x in [1,2,3] — 用 vector-length + vector-ref
                iter_val = translate_expr(stmt.iter)
                body_parts = translate_block(stmt.body)
                body_str = " ".join(body_parts)
                body_exprs.append(f"(let* ((__iter {iter_val}) (__n (vector-length __iter))) (do ((__i 0 (+ __i 1))) ((>= __i __n)) (let (({target} (vector-ref __iter __i))) {body_str})))")
            elif isinstance(stmt.iter, ast.Name):
                # for x in arr — arr 可能是 vector / tagged-array
                iter_name = stmt.iter.id
                body_parts = translate_block(stmt.body)
                body_str = " ".join(body_parts)
                body_exprs.append(f"(let* ((__iter {iter_name}) (__n (if (tagged-array? __iter) (tagged-array-len __iter) (vector-length __iter)))) (do ((__i 0 (+ __i 1))) ((>= __i __n)) (let (({target} (if (tagged-array? __iter) (float-array-ref (tagged-array-data __iter) __i) (vector-ref __iter __i)))) {body_str})))")
            else:
                body_exprs.append(f";; for loop (untranslated)")
        elif isinstance(stmt, ast.While):
            test = translate_expr(stmt.test)
            body_parts = translate_block(stmt.body)
            body_str = " ".join(body_parts)
            body_exprs.append(f"(let loop () (if {test} (begin {body_str} (loop))))")
        elif isinstance(stmt, ast.Expr):
            body_exprs.append(translate_expr(stmt.value))
        elif isinstance(stmt, ast.With):
            # with 语法糖：当前简化为直接执行 body，不实现上下文管理器
            body_scheme = " ".join(translate_block(stmt.body))
            body_exprs.append(body_scheme)
        elif isinstance(stmt, ast.Try):
            # try/except 语法糖：使用 guard 捕获异常
            body_scheme = " ".join(translate_block(stmt.body))
            handler_body = ""
            if stmt.handlers:
                handler_body = " ".join(translate_block(stmt.handlers[0].body))
            else:
                handler_body = "(void)"
            body_exprs.append(f"(guard (e (else {handler_body})) {body_scheme})")
        elif isinstance(stmt, ast.Raise):
            # raise Exception("msg") → (error 'user "msg")
            if stmt.exc and isinstance(stmt.exc, ast.Call) and isinstance(stmt.exc.func, ast.Name):
                msg = ""
                if stmt.exc.args:
                    msg = translate_expr(stmt.exc.args[0])
                body_exprs.append(f"(error '{stmt.exc.func.id} {msg})")
            else:
                body_exprs.append("(error 'raise \"raised\")")
        elif isinstance(stmt, ast.Assert):
            # assert cond, msg → (if (not cond) (error 'assert msg))
            test = translate_expr(stmt.test)
            msg = translate_expr(stmt.msg) if stmt.msg else "\"assertion failed\""
            body_exprs.append(f"(if (not {test}) (error 'assert {msg}))")
        elif isinstance(stmt, ast.Pass):
            body_exprs.append("(void)")
        elif isinstance(stmt, ast.Delete):
            # del a[i] → (dict-set! / vector-set! ...) 暂不支持
            body_exprs.append(f";; del: {ast.dump(stmt)}")
        else:
            body_exprs.append(f";; {type(stmt).__name__}: {ast.dump(stmt)}")
        si += 1
    
    # 生成函数体
    # 在每条表达式前添加源码行号注释
    annotated_exprs = []
    for idx, expr in enumerate(body_exprs):
        # si 可能因优化跳过某些 stmt，但 body_exprs 与 node.body 可能不完全一一对应
        stmt = node.body[min(idx, len(node.body) - 1)]
        ann = debug_annotation(stmt, source_file)
        if ann:
            annotated_exprs.append(ann)
        annotated_exprs.append(expr)
    
    if len(annotated_exprs) == 1:
        body = f"  {annotated_exprs[0]}"
    else:
        exprs_str = "\n    ".join(annotated_exprs)
        body = f"  (begin\n    {exprs_str}\n  )"
    
    # 将函数体内被赋值的变量绑定为局部变量，避免递归调用时覆盖全局变量
    param_names = {arg.arg for arg in node.args.args}
    local_vars = collect_assigned_names(node.body) - param_names
    if local_vars:
        bindings = " ".join(f"({mangle_name(v)} #f)" for v in sorted(local_vars))
        body = f"  (let ({bindings})\n{body}\n  )"
    
    # 如果函数体包含 return，用 call/cc 支持提前返回
    if has_return(node.body):
        body = f"  (call/cc (lambda (__return__)\n{body}\n  ))"
    
    # 恢复外层类型环境
    TYPE_ENV = saved_env
    CURRENT_TENSOR_VARS = saved_tensor_vars
    func_ann = debug_annotation(node, source_file)
    header = f"{func_ann}\n" if func_ann else ""
    return f"{header}(define ({name} {' '.join(args)})\n{body})"


def generate_extern_ffi():
    """生成 extern fn 的 Scheme foreign-procedure 声明"""
    lines = []
    loaded_libs = set()
    for name, info in EXTERN_FUNCTIONS.items():
        lib = info["lib"]
        # 加载库（每种库只加载一次）
        if lib == "openblas" and lib not in loaded_libs:
            lines.append('(load-shared-object "libopenblas.so.0")')
        elif lib == "lapack" and lib not in loaded_libs:
            lines.append('(load-shared-object "liblapacke.so")')
        elif lib == "xgboost" and lib not in loaded_libs:
            lines.append('(load-shared-object "/data/venv/lib/python3.12/site-packages/xgboost/lib/libxgboost.so")')
        elif lib == "cublas" and lib not in loaded_libs:
            lines.append('(load-shared-object "libcublas.so.12")')
        elif lib == "cudnn" and lib not in loaded_libs:
            lines.append('(load-shared-object "libcudnn.so.9")')
        elif lib == "onnxruntime" and lib not in loaded_libs:
            lines.append('(load-shared-object "libonnxruntime.so")')
        elif lib == "onnx_helper" and lib not in loaded_libs:
            lines.append('(load-shared-object "/tmp/libonnx_helper.so")')
        elif lib == "dgemm_row" and lib not in loaded_libs:
            lines.append('(load-shared-object "/home/quqiufeng/libdgemm_row.so")')
        elif lib == "stock_rl" and lib not in loaded_libs:
            lines.append('(load-shared-object "libstock_rl_helper.so")')
        elif lib == "torch_std" and lib not in loaded_libs:
            lines.append('(load-shared-object "libtorch_std_helper.so")')
        loaded_libs.add(lib)
        
        # 构建参数类型列表
        param_types = []
        for pname, ptype in info["params"]:
            ct = translate_type(ptype)
            param_types.append(ct)
        
        # 返回类型
        ret_c = TYPE_MAP.get(info["ret"], "void")
        
        # 生成 foreign-procedure 声明
        types_str = " ".join(param_types)
        lines.append(f"(define {name}")
        lines.append(f"  (foreign-procedure \"{name}\" ({types_str}) {ret_c}))")
    
    return "\n".join(lines)


def main():
    global TYPE_ENV, EXTERN_FUNCTIONS, IMPORTED_NAMES, RECORD_TYPES, RECORD_FIELDS, FUNCTION_SIGS, TYPE_WARNINGS, TYPECHECK_MODE

    # 检查命令行参数
    typecheck_mode = "strict"
    input_files = []
    i = 1
    while i < len(sys.argv):
        arg = sys.argv[i]
        if arg == "--warn" or arg == "-w":
            typecheck_mode = "warn"
        elif arg == "--strict":
            typecheck_mode = "strict"
        elif not arg.startswith("-"):
            input_files.append(arg)
        i += 1

    set_typecheck_mode(typecheck_mode)
    TYPE_WARNINGS = []

    try:
        _run_pipeline(input_files)
    except StaticPyTypeError as e:
        sys.exit(1)


def _run_pipeline(input_files):
    global TYPE_ENV, EXTERN_FUNCTIONS, IMPORTED_NAMES, RECORD_TYPES, RECORD_FIELDS, FUNCTION_SIGS, TYPE_WARNINGS

    if input_files:
        source_filename = input_files[0]
        with open(source_filename, "r") as f:
            code = f.read()
    else:
        source_filename = "<stdin>"
        code = sys.stdin.read()
    
    # 重置全局状态
    TYPE_ENV = {}
    EXTERN_FUNCTIONS = {}
    IMPORTED_NAMES = {}
    RECORD_TYPES = {}
    RECORD_FIELDS = {}
    FUNCTION_SIGS = {}
    TYPE_WARNINGS = []
    
    # 提取 extern fn 声明
    code = parse_extern_functions(code)
    
    # 使用 Python 的 ast 解析
    tree = ast.parse(code)
    tree.source_file = source_filename
    
    # 解析 import / from ... import
    parse_imports(tree)
    
    # 收集记录类型
    collect_record_types(tree)
    
    # 生成 Scheme
    output_parts = []
    
    # 类型检查
    typecheck_module(tree)
    
    # 检查 main 函数存在性（缺少则后端编译必然失败）
    has_main = any(isinstance(node, ast.FunctionDef) and node.name == "main" for node in tree.body)
    if not has_main:
        typecheck_error(None, "missing main function")
    ffi = generate_extern_ffi()
    if ffi:
        output_parts.append(";; extern FFI functions")
        output_parts.append(ffi)
        output_parts.append("")
    
    # Source filename for error messages
    source_filename = getattr(tree, 'source_file', '<input>')
    output_parts.append(f";; Source: {source_filename}")
    output_parts.append("")
    
    # 函数定义（跳过 import 语句）
    output_parts.append(";; StaticPy functions")
    for node in tree.body:
        if isinstance(node, (ast.Import, ast.ImportFrom)):
            continue
        if isinstance(node, ast.ClassDef):
            output_parts.append(translate_class(node))
        elif isinstance(node, ast.FunctionDef):
            output_parts.append(translate_function(node, source_filename))
    
    # 顶层表达式（调用 main）
    output_parts.append("")
    output_parts.append(";; Entry point")
    output_parts.append("(static_main)")
    
    # 输出 Scheme 代码（类型警告已提前输出到 stderr，不再混入生成文件）
    print("\n".join(output_parts))
    
    # 输出普通警告（仍作为注释追加，通常不影响 Scheme 解析）
    if WARNINGS:
        print("\n;;=== WARNINGS ===")
        for w in WARNINGS:
            print(f";;{w}")


if __name__ == "__main__":
    main()
