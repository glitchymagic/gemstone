#!/usr/bin/env python3
"""Dump the game's 0xB0-byte bone node records from a RAM dump.
Record: +0x00 u16 flag, s16 parent, ... +0x10 s32 rot x/y/z (65536 = 360 deg), +0x2C f32 scale[3],
+0x50 u32 mesh ptr (into a loaded .MDL), +0x58 f32 offset[3], +0x64 f32 offset copy, +0x70 f32 world 4x4."""
import struct, sys, os, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import psmdl
ram = open(sys.argv[1], 'rb').read(); B = 0x0C000000
start = int(sys.argv[2], 16); count = int(sys.argv[3])
mdls = {}
for name in sys.argv[4:]:
    m = open(name, 'rb').read(); i = ram.find(m[0x100:0x140])
    if i >= 0:
        parts, _, _ = psmdl.parse(m)
        for pi, p in enumerate(parts): mdls[B + i - 0x100 + p['ofs']] = (os.path.basename(name), pi)
out = []
for k in range(count):
    o = start - B + k * 0xB0
    flag, parent = struct.unpack_from('<Hh', ram, o)
    rot = struct.unpack_from('<3i', ram, o + 0x10)
    sc = struct.unpack_from('<3f', ram, o + 0x2C)
    ptr = struct.unpack_from('<I', ram, o + 0x50)[0]
    off = struct.unpack_from('<3f', ram, o + 0x58); off2 = struct.unpack_from('<3f', ram, o + 0x64)
    wt = struct.unpack_from('<3f', ram, o + 0xA0)
    who = mdls.get(ptr, ('-', -1) if ptr == 0 else (hex(ptr), -1))
    out.append({'slot': k, 'flag': flag, 'parent': parent, 'mesh': who, 'rot': rot, 'off': off, 'off2': off2, 'world_t': wt, 'scale': sc})
    print(k, 'flag', flag, 'par', parent, who, 'rot', rot, 'off (%.2f %.2f %.2f)' % off, 'cur (%.2f %.2f %.2f)' % off2, 'W (%.1f %.1f %.1f)' % wt)
if len(sys.argv) > 4: json.dump(out, open('/tmp/nodes.json', 'w'))
