#!/usr/bin/env python3
"""Extract the ISO9660 filesystem from a GD-ROM high-density track (2352-byte raw sectors).
Usage: gdi_extract.py <track3.bin> <start_lba> <outdir>"""
import os, struct, sys

trk, start, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
f = open(trk, 'rb')

def sector(lba):
    f.seek((lba - start) * 2352 + 16)
    return f.read(2048)

def read_extent(lba, size):
    buf = bytearray()
    n = (size + 2047) // 2048
    f.seek((lba - start) * 2352)
    raw = f.read(n * 2352)
    for i in range(n):
        buf += raw[i * 2352 + 16:i * 2352 + 16 + 2048]
    return bytes(buf[:size])

pvd = sector(start + 16)
assert pvd[1:6] == b'CD001', pvd[:8]
root = pvd[156:156 + 34]
inv = []

def walk(lba, size, path):
    data = read_extent(lba, size)
    i = 0
    while i < len(data):
        l = data[i]
        if l == 0:
            i = (i // 2048 + 1) * 2048
            continue
        rec = data[i:i + l]
        elba = struct.unpack_from('<I', rec, 2)[0]
        esz = struct.unpack_from('<I', rec, 10)[0]
        flags = rec[25]
        nl = rec[32]
        name = rec[33:33 + nl]
        i += l
        if name in (b'\x00', b'\x01'):
            continue
        name = name.decode('ascii', 'replace').split(';')[0]
        p = os.path.join(path, name)
        if flags & 2:
            os.makedirs(os.path.join(out, p), exist_ok=True)
            walk(elba, esz, p)
        else:
            with open(os.path.join(out, p), 'wb') as o:
                o.write(read_extent(elba, esz))
            inv.append((p, elba, esz))

walk(struct.unpack_from('<I', root, 2)[0], struct.unpack_from('<I', root, 10)[0], '')
with open(os.path.join(out, '..', 'inventory.tsv'), 'w') as o:
    for p, l, s in sorted(inv):
        o.write(f'{p}\t{l}\t{s}\n')
print(len(inv), 'files', sum(s for _, _, s in inv), 'bytes')
