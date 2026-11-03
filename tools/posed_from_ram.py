#!/usr/bin/env python3
"""Pose a fighter exactly as the game had it in a RAM dump: each part's vertices times the game's own
world matrix for that bone (node record - 0x40, row-vector 4x4). Writes OBJ/MTL (+ textures) and a
camera hint (in front of the fighter's face). Usage: posed_from_ram.py ram.bin X.MDL X_MODEL.BIN skel.json outdir [texdir] [parts]"""
import json, os, struct, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import psmdl, export_obj
ram = open(sys.argv[1], 'rb').read(); B = 0x0C000000
mdlp, mbp, skelp, out = sys.argv[2:6]
texdir = sys.argv[6] if len(sys.argv) > 6 and sys.argv[6] != '-' else None
show = set(map(int, sys.argv[7].split(','))) if len(sys.argv) > 7 else None
mdl = open(mdlp, 'rb').read(); parts, tex, _ = psmdl.parse(mdl)
i = ram.find(mdl[0x100:0x140]); base = B + i - 0x100
ptr2part = {base + p['ofs']: k for k, p in enumerate(parts)}
W = {}
for o in range(0x50, len(ram) - 0x60, 4):
    v = struct.unpack_from('<I', ram, o)[0]
    if v in ptr2part and struct.unpack_from('<H', ram, o - 0x50)[0] == 1:
        r = o - 0x50; M = np.array(struct.unpack_from('<16f', ram, r - 0x40)).reshape(4, 4)
        if abs(M[3, 3] - 1) < 1e-3 and abs(np.linalg.det(M[:3, :3]) - 1) < 0.05: W.setdefault(ptr2part[v], M)
export_obj.export(mdlp, mbp, out, only=set(), name='tmp')   # textures + mtl
if texdir:
    import shutil
    for f in os.listdir(texdir): shutil.copy(os.path.join(texdir, f), os.path.join(out, f))
lines = ['mtllib tmp.mtl']; vi = 1
for pi, p in enumerate(parts):
    if pi not in W or not p['mats'] or (show is not None and pi not in show): continue
    M = W[pi]; lines.append(f'o part{pi:02d}')
    for m in p['mats']:
        lines.append('usemtl ' + (f't{m["tex"]:02d}' if m['tex'] < len(tex) else 'flat'))
        for sf, verts in m['strips']:
            for v in verts:
                pw = np.array([*v[:3], 1.0]) @ M; nw = np.array(v[3:6]) @ M[:3, :3]
                lines.append('v %.4f %.4f %.4f' % tuple(pw[:3])); lines.append('vn %.4f %.4f %.4f' % tuple(nw)); lines.append('vt %.5f %.5f' % (v[6], 1 - v[7]))
            for a, b, c in psmdl.strips_to_tris(sf, verts):
                lines.append('f ' + ' '.join(f'{vi + k}/{vi + k}/{vi + k}' for k in (a, b, c)))
            vi += len(verts)
open(f'{out}/posed.obj', 'w').write('\n'.join(lines) + '\n')
R = W[0]; head = W.get(4, R)
fwd = R[2, :3] / np.linalg.norm(R[2, :3])
cam = {'target': (W[1][3, :3] * 0.5 + head[3, :3] * 0.5).tolist(), 'forward': fwd.tolist(), 'root': R[3, :3].tolist()}
json.dump(cam, open(f'{out}/cam.json', 'w'))
print('posed parts', sorted(W), 'cam', {k: [round(x, 1) for x in v] for k, v in cam.items()})
