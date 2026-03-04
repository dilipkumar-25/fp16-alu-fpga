import numpy as np
import struct

def fp16_to_bits(value):
    """Convert a Python float to FP16 bit pattern"""
    fp16_val = np.float16(value)
    bits = np.frombuffer(fp16_val.tobytes(), dtype=np.uint16)[0]
    return bits

def bits_to_fp16(bits):
    """Convert FP16 bit pattern back to float"""
    byte_val = np.array(bits, dtype=np.uint16).tobytes()
    return np.frombuffer(byte_val, dtype=np.float16)[0]

def unpack_fp16(bits):
    """Extract sign, exponent, mantissa from FP16 bit pattern"""
    sign     = (bits >> 15) & 0x1
    exponent = (bits >> 10) & 0x1F
    mantissa = bits & 0x3FF
    return sign, exponent, mantissa

def fp16_add(a_bits, b_bits):
    a = bits_to_fp16(a_bits)
    b = bits_to_fp16(b_bits)
    result = np.float16(a) + np.float16(b)
    return fp16_to_bits(result)

def fp16_mul(a_bits, b_bits):
    a = bits_to_fp16(a_bits)
    b = bits_to_fp16(b_bits)
    result = np.float16(a) * np.float16(b)
    return fp16_to_bits(result)

def fp16_sub(a_bits, b_bits):
    a = bits_to_fp16(a_bits)
    b = bits_to_fp16(b_bits)
    result = np.float16(a) - np.float16(b)
    return fp16_to_bits(result)

def fp16_mac(a_bits, b_bits, c_bits):
    """Multiply-Accumulate: a*b + c"""
    a = bits_to_fp16(a_bits)
    b = bits_to_fp16(b_bits)
    c = bits_to_fp16(c_bits)
    result = np.float16(np.float32(a) * np.float32(b) + np.float32(c))
    return fp16_to_bits(result)

# --- Test it ---
if __name__ == "__main__":
    a = fp16_to_bits(1.5)
    b = fp16_to_bits(2.0)
    
    print(f"1.5  in FP16 bits: {a:016b} (0x{a:04X})")
    print(f"2.0  in FP16 bits: {b:016b} (0x{b:04X})")
    
    result_add = fp16_add(a, b)
    print(f"1.5 + 2.0 = {bits_to_fp16(result_add)} → bits: {result_add:016b}")
    
    result_mul = fp16_mul(a, b)
    print(f"1.5 * 2.0 = {bits_to_fp16(result_mul)} → bits: {result_mul:016b}")
    
    sign, exp, mant = unpack_fp16(a)
    print(f"\nUnpacking 1.5:")
    print(f"  Sign={sign}, Exponent={exp} (actual={exp-15}), Mantissa={mant:010b}")
    