# Power Stone (DC) arcade ladder row pick, reproduced from 1ST_READ code at 0x8C0A4816..0x8C0A4850.
def lcg(s):            # rand() 0x8C0DF920: state u32 at 0x8C346A50, initial value 1 (never reseeded)
    s = (s * 1103515245 + 12345) & 0xFFFFFFFF
    return s, (s >> 16) & 0x7FFF

def row_from_rand(r):  # frand() = r * 2**-15 (0x8C0DF940); row = (u32)(frand()*255.0) % 8  (__modlu 0x8C0E6F24)
    return ((r * 255) >> 15) % 8   # exact: r*255 < 2**24, so the float math is exact

def pick_row(state):   # state = RNG word read just before the select screen opens; returns (row, new_state)
    state, r = lcg(state)
    return row_from_rand(r), state

if __name__ == '__main__':
    import struct, sys
    s = 1; rows = {}
    for k in range(1, 200001):
        s, r = lcg(s); rows[k] = row_from_rand(r)
    for k in (10605, 10704, 10757, 10838, 10858, 11260, 10824, 10839, 10841, 10855, 10862, 10912, 11004, 10834, 10748, 10857, 10971):
        print(k, 'row produced by call #%d =' % k, rows[k], ' prev calls:', [rows[k - i] for i in range(1, 8)])
