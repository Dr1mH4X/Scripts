import math

def get_bit_length(n):
    return math.floor(math.log2(n)) + 1

n = int(input("Enter data: "))

bit_length = get_bit_length(n)
print(f"this data's bits is: {bit_length}")
