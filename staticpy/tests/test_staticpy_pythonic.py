import math
import random
import json
import os
import os.path
import time

def main():
    x: float = math.sin(3.14)
    r: float = random.random()
    i: int = random.randint(0, 100)
    data = json.loads('{"a": 1, "b": [2, 3]}')
    s: str = json.dumps(data)
    cwd: str = os.getcwd()
    exists: bool = os.path.exists("/tmp")
    ts: float = time.time()
    print(x)
    print(r)
    print(i)
    print(s)
    print(cwd)
    print(exists)
    print(ts)
    if exists and i >= 0 and i <= 100 and len(s) > 0:
        print("PYTHONIC OK")
    else:
        print("PYTHONIC FAIL")
