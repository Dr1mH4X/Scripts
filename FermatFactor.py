import gmpy2
import time

def fermat_factorization(n):
    """
    Fermat因式分解算法 - 仅知道N时使用
    
    参数:
        n: 待分解的合数
    返回:
        (p, q): n的两个因数，如果分解失败返回None
    """
    # 检查输入是否为奇数
    if n % 2 == 0:
        # 如果是偶数，先提取因子2
        print(f"N是偶数，一个因子是2")
        return 2, n // 2
    
    # 检查是否为完全平方数
    sqrt_n = gmpy2.isqrt(n)
    if sqrt_n * sqrt_n == n:
        print(f"N是完全平方数：{sqrt_n}²")
        return sqrt_n, sqrt_n
    
    # 从ceil(sqrt(n))开始搜索
    a = gmpy2.isqrt(n) + 1
    
    # 设置最大迭代次数防止无限循环
    max_iterations = 1000000  # 可根据需要调整
    iterations = 0
    
    print(f"开始Fermat分解，N = {n}")
    print(f"初始a = {a}")
    
    while iterations < max_iterations:
        # 计算 b² = a² - n
        b_squared = gmpy2.square(a) - n
        
        # 检查b²是否为完全平方数
        if gmpy2.is_square(b_squared):
            b = gmpy2.isqrt(b_squared)
            p = a + b
            q = a - b
            
            # 验证分解结果
            if p * q == n and p > 1 and q > 1:
                print(f"分解成功！迭代次数：{iterations + 1}")
                print(f"a = {a}, b = {b}")
                return max(p, q), min(p, q)  # 返回较大因数在前
        
        a += 1
        iterations += 1
        
        # 每10000次迭代显示进度
        if iterations % 10000 == 0:
            print(f"已迭代 {iterations} 次，当前a = {a}")
    
    print(f"分解失败：在{max_iterations}次迭代内未找到因数")
    return None

def analyze_factorization_difficulty(n):
    """
    分析因式分解的难度
    """
    print(f"\n=== 分解难度分析 ===")
    print(f"N = {n}")
    print(f"N的位数：{len(str(n))}")
    print(f"sqrt(N) ≈ {gmpy2.isqrt(n)}")
    
    # 估算两个因数的差值对算法效率的影响
    sqrt_n = gmpy2.isqrt(n)
    print(f"如果两个因数差值较小，算法会很快")
    print(f"如果两个因数差值很大（如一个接近sqrt(N)，一个很小），算法会很慢")

# 主函数
if __name__ == "__main__":
    # 如果你有一个具体的N值，在这里替换
    # 示例：使用之前代码中的大数N
    N = 221

    # 分析N的特征
    analyze_factorization_difficulty(N)
    
    # 执行分解
    print("\n=== 开始Fermat分解 ===")
    start_time = time.time()
    result = fermat_factorization(N)
    end_time = time.time()
    
    if result:
        p, q = result
        print(f"\n=== 分解成功 ===")
        print(f"因数1：{p}")
        print(f"因数2：{q}")
        print(f"验证：{p} × {q} = {p * q}")
        print(f"是否等于原N：{p * q == N}")
        print(f"总用时：{end_time - start_time:.4f}秒")
        
        # 分析因数特征
        print(f"\n=== 因数分析 ===")
        print(f"两个因数的差值：{abs(p - q)}")
        print(f"两个因数的比值：{max(p, q) / min(p, q):.6f}")
    else:
        print("分解失败")