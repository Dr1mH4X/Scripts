# RSAScripts - RSA 密码学攻击工具集

个人使用的RSA攻击脚本集合。

---

## 脚本功能一览

| 脚本名 | 功能 | 适用场景 |
|--------|------|----------|
| **`BytesToLong.py`** | 将字节串转为大整数 | 读取密文、密钥、模数等 |
| **`calcbits.py`** | 计算大整数的位数（bit length） | 快速判断密钥强度 |
| **`ChineseRemainderTheorem.py`** | 中国剩余定理（CRT）求解 | 批量解密、RSA 私钥重构 |
| **`CommonModulusAttack.py`** | **共模攻击**（同一模数，不同公钥） | CTF 经典题型 |
| **`CommonModulusAttack_PLUS.py`** | 共模攻击 **增强版**（支持多组密文） | 复杂共模场景 |
| **`FermatFactor.py`** | **费马分解法**（当 p、q 接近时） | 快速分解模数 N |
| **`SharedPrimeAttack.py`** | **共享素数攻击**（多个 RSA 使用相同 p 或 q） | 多用户系统攻击 |
