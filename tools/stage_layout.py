#!/usr/bin/env python3
"""Stage object placement straight from RAM (dump taken during a fight on that stage): every stage object is a
0xA4-byte record holding a pointer to its part inside the loaded STGn0.MDL; its 4x4 row-vector world matrix sits
at pointer-0x4C, a flags word at pointer+8; the float at pointer-4 is 1.4 for exactly the poles (Londo's lamp posts, the
dojo's pillars, the ship's masts: the tall thin parts every stage has 2-3 of; pole swing targets). Usage: stage_layout.py ram.bin STG00.MDL out.json"""
import json, os, struct, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mocap, psmdl
ram = open(sys.argv[1], 'rb').read(); B = 0x0C000000
parts, base, _ = mocap.find_records(ram, sys.argv[2], 0)
p2 = {base + p['ofs']: k for k, p in enumerate(parts)}
a = np.frombuffer(ram[:len(ram) // 4 * 4], dtype='<u4')
out = []
for i in np.nonzero(np.isin(a, np.array(list(p2), dtype=np.uint32)))[0]:
    o = int(i) * 4
    M = np.array(struct.unpack_from('<16f', ram, o - 0x4C)).reshape(4, 4)
    if abs(M[3, 3] - 1) > 1e-3 or abs(abs(np.linalg.det(M[:3, :3])) - 1) > 0.05: continue   # not an object record
    flags = struct.unpack_from('<I', ram, o + 8)[0]
    d = {'part': p2[int(a[i])], 'addr': hex(B + o), 'M': M.round(4).tolist(), 'flags': hex(flags)}
    if abs(struct.unpack_from('<f', ram, o - 4)[0] - 1.4) < 1e-4: d['pole'] = True
    out.append(d)
json.dump(out, open(sys.argv[3], 'w'), indent=1)
print(len(out), 'instances:', ' '.join(f"{d['part']}@({d['M'][3][0]:.0f},{d['M'][3][1]:.0f},{d['M'][3][2]:.0f})" for d in out))
