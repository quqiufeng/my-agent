# 测试 Any / 警告模式 / 更多 Python 语法

def add(a: int, b: int) -> int:
    return a + b

def flexible(x: Any) -> Any:
    return x

def main():
    # Any 类型：可以赋任何值
    a: Any = 1
    a = "hello"
    a = [1.0, 2.0]
    
    # 无标注变量：推断为 Any 风格，不强制类型
    b = 10
    b = "string"
    
    # 元组解构
    x, y = 1, 2
    print(x)
    print(y)
    
    # range 多参数
    s = 0
    for i in range(1, 5):
        s = s + i
    print(s)
    
    # for in list
    total = 0.0
    arr = [1.0, 2.0, 3.0]
    for v in arr:
        total = total + v
    print(total)
    
    # 列表推导式
    squares = [i * i for i in range(5)]
    print(len(squares))
    
    # try/except 语法糖
    try:
        r = add(1, 2)
        print(r)
    except:
        print("ERROR")
    
    # assert
    assert add(1, 2) == 3
    
    # raise 语法糖
    try:
        raise ValueError("test error")
    except:
        pass

    # del 语法糖（当前仅输出注释，不实际删除）
    tmp = {"key": 1}
    del tmp["key"]

    print("SUPERSET OK")
