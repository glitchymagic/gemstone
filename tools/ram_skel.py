#!/usr/bin/env python3
"""Find a fighter's skeleton in a Dreamcast main-RAM dump (16 MB from 0x0C000000):
locate the loaded .MDL, then every RAM word pointing at one of its parts, and print the
structures around those pointers (node records: parent links, offsets, rotations, matrices)."""
import struct, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import psmdl
ram = open(sys.argv[1], 'rb').read()
mdl = open(sys.argv[2], 'rb').read()
parts, tex, _ = psmdl.parse(mdl)
base = ram.find(mdl[:256])
if base < 0:   # the loader patches headers; anchor on vertex data instead
    i = ram.find(mdl[0x100:0x140]); base = i - 0x100 if i >= 0 else -1
print('MDL in RAM at', hex(0x0C000000 + base) if base >= 0 else None)
if base < 0: sys.exit()
targets = {}
for i, p in enumerate(parts):
    for hb in (0x0C000000, 0x8C000000, 0xAC000000):
        targets[hb + base + p['ofs']] = i
hits = []
for o in range(0, len(ram) - 4, 4):
    v = struct.unpack_from('<I', ram, o)[0]
    if v in targets: hits.append((o, targets[v]))
print(len(hits), 'pointer hits')
for o, i in hits[:80]:
    fl = struct.unpack_from('<12f', ram, o - 16)
    print(hex(0x0C000000 + o), 'part', i, ' '.join('%.3g' % x for x in fl))
