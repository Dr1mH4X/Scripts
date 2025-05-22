#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
RSA共模攻击脚本
支持多个e和c的共模攻击，自动寻找互质的e值进行攻击
"""

import gmpy2
from itertools import combinations
import binascii

def extended_gcd(a, b):
    """
    扩展欧几里得算法
    返回 (gcd, x, y) 使得 ax + by = gcd(a, b)
    """
    if a == 0:
        return b, 0, 1
    gcd, x1, y1 = extended_gcd(b % a, a)
    x = y1 - (b // a) * x1
    y = x1
    return gcd, x, y

def common_modulus_attack(n, e1, c1, e2, c2):
    """
    RSA共模攻击 - 针对两个互质的e值
    
    参数:
        n: 公共模数
        e1, e2: 两个公钥指数（必须互质）
        c1, c2: 对应的密文
    
    返回:
        明文m，如果攻击成功
    """
    # 检查e1和e2是否互质
    gcd_e, s, t = extended_gcd(e1, e2)
    
    if gcd_e != 1:
        return None, f"e1={e1} 和 e2={e2} 不互质，gcd={gcd_e}"
    
    print(f"找到互质的e值对：e1={e1}, e2={e2}")
    print(f"扩展欧几里得算法结果：{e1}*{s} + {e2}*{t} = {gcd_e}")
    
    # 计算明文 m = c1^s * c2^t mod n
    # 需要处理负指数的情况
    if s < 0:
        # 计算 c1 的模逆
        c1_inv = gmpy2.invert(c1, n)
        m = gmpy2.powmod(c1_inv, -s, n)
    else:
        m = gmpy2.powmod(c1, s, n)
    
    if t < 0:
        # 计算 c2 的模逆
        c2_inv = gmpy2.invert(c2, n)
        m = (m * gmpy2.powmod(c2_inv, -t, n)) % n
    else:
        m = (m * gmpy2.powmod(c2, t, n)) % n
    
    return m, "攻击成功"

def multi_common_modulus_attack(n, ec_pairs):
    """
    多个e,c对的共模攻击
    自动寻找互质的e值进行攻击
    
    参数:
        n: 公共模数
        ec_pairs: [(e1, c1), (e2, c2), (e3, c3), ...] 列表
    
    返回:
        所有成功攻击的结果
    """
    results = []
    successful_attacks = []
    
    print(f"共有 {len(ec_pairs)} 个 (e, c) 对")
    print("开始寻找互质的e值对进行攻击...\n")
    
    # 遍历所有可能的e值对组合
    for i, (e1, c1) in enumerate(ec_pairs):
        for j, (e2, c2) in enumerate(ec_pairs):
            if i >= j:  # 避免重复计算
                continue
                
            print(f"尝试攻击：e1={e1}, e2={e2}")
            
            # 执行共模攻击
            result, status = common_modulus_attack(n, e1, c1, e2, c2)
            
            if result is not None:
                print(f"✓ {status}")
                print(f"  明文(十进制): {result}")
                
                # 尝试转换为可读格式
                try:
                    # 转换为十六进制
                    hex_result = hex(result)[2:]
                    if len(hex_result) % 2:
                        hex_result = '0' + hex_result
                    
                    # 尝试转换为ASCII
                    try:
                        ascii_result = binascii.unhexlify(hex_result).decode('ascii', errors='ignore')
                        if ascii_result.isprintable():
                            print(f"  明文(ASCII): {ascii_result}")
                    except:
                        pass
                    
                    print(f"  明文(十六进制): {hex_result}")
                    
                except Exception as e:
                    print(f"  格式转换失败: {e}")
                
                successful_attacks.append({
                    'e1': e1, 'e2': e2,
                    'plaintext_dec': result,
                    'plaintext_hex': hex(result)[2:]
                })
                
                print(f"  验证: {result}^{e1} ≡ {gmpy2.powmod(result, e1, n)} (mod n)")
                print(f"        {result}^{e2} ≡ {gmpy2.powmod(result, e2, n)} (mod n)")
                print(f"        c1 = {c1}")
                print(f"        c2 = {c2}")
                print(f"        验证结果: {gmpy2.powmod(result, e1, n) == c1 and gmpy2.powmod(result, e2, n) == c2}")
                
            else:
                print(f"✗ {status}")
            
            print("-" * 60)
    
    return successful_attacks

def hex_to_int(hex_str):
    """十六进制字符串转整数"""
    return int(hex_str.replace('0x', ''), 16)

def custom_attack():
    """
    自定义攻击函数 - 用户可以输入自己的参数
    """
    print("\n=== 自定义共模攻击 ===")
    print("请输入攻击参数：")
    
    try:
        # 输入公共模数
        n_input = input("请输入公共模数 n (十进制或0x开头的十六进制): ").strip()
        if n_input.startswith('0x'):
            n = hex_to_int(n_input)
        else:
            n = int(n_input)
        
        # 输入e,c对的数量
        pair_count = int(input("请输入(e,c)对的数量: "))
        
        ec_pairs = []
        for i in range(pair_count):
            print(f"\n第 {i+1} 对:")
            e = int(input(f"  请输入 e{i+1}: "))
            
            c_input = input(f"  请输入 c{i+1} (十进制或0x开头的十六进制): ").strip()
            if c_input.startswith('0x'):
                c = hex_to_int(c_input)
            else:
                c = int(c_input)
            
            ec_pairs.append((e, c))
        
        print(f"\n攻击参数确认:")
        print(f"  n = {n}")
        for i, (e, c) in enumerate(ec_pairs):
            print(f"  e{i+1} = {e}, c{i+1} = {c}")
        
        # 执行攻击
        results = multi_common_modulus_attack(n, ec_pairs)
        
        if results:
            print(f"\n攻击成功！共找到 {len(results)} 个解:")
            for i, result in enumerate(results):
                print(f"解 {i+1}: {result['plaintext_dec']}")
        else:
            print("\n攻击失败：未找到互质的e值对或攻击失败")
            
    except Exception as e:
        print(f"输入错误: {e}")

if __name__ == "__main__":
    custom_attack()