import torch
from torch import matmul

def main():
    if torch.available():
        a = torch.ones(2, 2)
        b = torch.zeros(2, 2)
        c = matmul(a, b)
        lst = torch.to_list(c)
        print(lst[0])
        print(lst[3])
        if lst[0] == 0.0 and lst[3] == 0.0:
            print("TORCH MATMUL OK")
        else:
            print("TORCH MATMUL FAIL")
    else:
        print("TORCH NOT AVAILABLE")
