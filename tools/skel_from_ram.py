#!/usr/bin/env python3
"""Skeleton for one fighter form from a RAM dump: every 0xB0-byte node record whose mesh pointer
(+0x50) hits a part of the loaded .MDL gives that part's parent (byte +3, a slot index relative to the
form's part-0 record) and bone offset (+0x58). Writes skel JSON for export_glb.py.
Usage: skel_from_ram.py ram.bin X.MDL out.json [node_array_start_hex]"""
import json, os, struct, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import psmdl
ram = open(sys.argv[1], 'rb').read(); B = 0x0C000000
mdl = open(sys.argv[2], 'rb').read()
parts, _, _ = psmdl.parse(mdl)
import mocap
_, base, _ = mocap.find_records(ram, sys.argv[2], 0)
ptr2part = {base + p['ofs']: k for k, p in enumerate(parts)}
cand = {}
for o in range(0, len(ram) - 0xB0, 4):
    v = struct.unpack_from('<I', ram, o)[0]
    if v in ptr2part and o >= 0x50:
        r = o - 0x50
        if struct.unpack_from('<H', ram, r)[0] & 0xFF != 1: continue   # 0x0101 = second list (braids, ribbons, swords)
        cand.setdefault(ptr2part[v], []).append(r)
# root = the part-0 record with the most other parts' records on its 0xB0 grid
root = max(cand.get(0, []), key=lambda r0: sum(any((r - r0) % 0xB0 == 0 for r in rs) for rs in cand.values()))
recs = {}
for p, rs in cand.items():
    al = [r for r in rs if (r - root) % 0xB0 == 0]
    recs[p] = min(al, key=lambda r: abs(r - root)) if al else rs[0]
slot2part = {}
for p, r in recs.items():
    if (r - root) % 0xB0 == 0 and ram[r + 1] != 1: slot2part.setdefault((r - root) // 0xB0, p)
# second list (flag 0x0101): byte +2 = list (1), byte +3 = slot in that list or, for the list's first record, a body slot.
# The list's slot 0 (its anchor) is either itself flagged 0x0101 (Rouge: 01 01 01 0b, b3 = body slot) or the plain body
# record just before the first flagged one (Wang-Tang: 01 00 00 04, then 01 01 01 00 = child of list slot 0, which can't
# be itself).
l1 = sorted(r for r in recs.values() if ram[r + 1] == 1)
grid2part = {(r - root) // 0xB0: p for p, r in recs.items() if (r - root) % 0xB0 == 0}
base1 = None
if l1:
    base1 = (l1[0] - root) // 0xB0 - (1 if ram[l1[0] + 3] == 0 else 0)
parent = [-1] * len(parts); offset = [[0, 0, 0]] * len(parts)
for p, r in recs.items():
    pb = ram[r + 3]
    if ram[r + 1] == 1 and l1 and (r - root) // 0xB0 != base1:
        parent[p] = grid2part.get(base1 + pb, -1)
    else:
        parent[p] = -1 if pb == 0xFF else slot2part.get(pb, -1)
    offset[p] = [round(x, 4) for x in struct.unpack_from('<3f', ram, r + 0x58)]
missing = [k for k in range(len(parts)) if k not in recs and parts[k]['mats']]
out = {'parent': parent, 'offset': offset, 'ram_base': hex(base), 'missing': missing}
json.dump(out, open(sys.argv[3], 'w'), indent=1)
print(os.path.basename(sys.argv[2]), 'records', len(recs), 'of', len(parts), 'missing meshes', missing)
print('parent', parent)
