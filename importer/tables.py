#!/usr/bin/env python3
"""Tables the remaster's code uses, read out of YOUR copy of the game's program (1ST_READ.BIN, Power Stone USA).
Writes game/assets/disc/tables.json. Addresses are where the original keeps each table in memory (1ST_READ loads at
0x8C010000; SH-4 is little-endian). Usage: tables.py 1ST_READ.BIN out.json"""
import json, struct, sys

BASE = 0x0C010000


def off(addr):
    return (addr & 0x0FFFFFFF) - BASE


def f32(b, addr, n):
    return [round(x, 9) for x in struct.unpack_from('<%df' % n, b, off(addr))]


def u8(b, addr, n):
    return list(b[off(addr):off(addr) + n])


def u16(b, addr, n):
    return list(struct.unpack_from('<%dH' % n, b, off(addr)))


def lists(b, addr, n):
    """n records of (u32 pointer, u32 count) -> the byte lists they point at"""
    out = []
    for i in range(n):
        p, c = struct.unpack_from('<II', b, off(addr) + 8 * i)
        out.append(u8(b, p, c))
    return out


# name: (reader, address, count, int?)  -- what each one is: docs/RIP.md, docs/HITS.md, docs/CPU.md, docs/ITEMS.md
SPEC = {
    'combo_scale': (f32, 0x0C32E0A4, 16, False),        # damage scale by hits in a row
    'cpu_atk': (f32, 0x0C32DF78, 32, False),            # the CPU's hits x this, by level
    'cpu_def': (f32, 0x0C32DFF8, 32, False),            # hits on the CPU / this, by level
    'select_slots': (u8, 0x8C152619, 10, True),         # player number in each select-screen slot
    'item_cat_seq': (u8, 0x0C33CF54, 10, True),         # item category by the chest number in the round
    'item_cats': (lists, 0x0C33CF14, 4, True),          # the items in each category
    'item_cats_kraken': (lists, 0x0C33CF34, 4, True),   # same on Kraken's ship
    'cpu_dirs': (u16, 0x0C32D7E8, 8, True),             # the CPU's pad direction bits by heading octant
}


def build(b):
    t, ints = {}, []
    for name, (rd, addr, n, is_int) in SPEC.items():
        t[name] = rd(b, addr, n)
        if is_int:
            ints.append(name)
    return {'source': '1ST_READ.BIN (your disc)', 'tables': t, 'ints': ints}


def main():
    b = open(sys.argv[1], 'rb').read()
    json.dump(build(b), open(sys.argv[2], 'w'), indent=1)
    print('tables:', len(SPEC), '->', sys.argv[2])


if __name__ == '__main__':
    main()
