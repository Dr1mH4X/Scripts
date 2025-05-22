import gmpy2
from functools import reduce
import libnum

# 将 n 和 c 放入以下列表中
e = 3

n1 = ...
c1 = ...

n2 = ...
c2 = ...

ne = ...
ce = ...
ns = [n1, n2, ..., ne]  # 至少 e 个不同的 n
cs = [c1, c2, ..., ce]  # 与之对应的密文

# 计算 N = n1 * n2 * ... * ne
N = reduce(lambda x, y: x * y, ns)

# 应用中国剩余定理合并密文
def crt(cs, ns):
    total = 0
    N = reduce(lambda x, y: x * y, ns)
    for c_i, n_i in zip(cs, ns):
        m_i = N // n_i
        inv = gmpy2.invert(m_i, n_i)
        total += c_i * m_i * inv
    return total % N

C = crt(cs, ns)
# m^e ≈ C, 求 m = C 的 e 次整数根
m = gmpy2.iroot(C, e)[0]
# 将整数 m 转换为字符串
print(libnum.n2s(int(m)))