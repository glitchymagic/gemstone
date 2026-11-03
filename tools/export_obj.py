#!/usr/bin/env python3
"""MDL + MODEL.BIN -> OBJ/MTL + PNG textures (one 'o' group per part, local space).
Usage: export_obj.py <X.MDL> <X_MODEL.BIN> <outdir> [part,part,...]"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import psmdl, pstex

def tri_ok(a, b, c):
    # orient by agreement with the stored vertex normals
    ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
    vx, vy, vz = c[0] - a[0], c[1] - a[1], c[2] - a[2]
    nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
    if nx * nx + ny * ny + nz * nz < 1e-12: return None
    s = sum(nx * v[3] + ny * v[4] + nz * v[5] for v in (a, b, c))
    return s >= 0

def export(mdl, mb, out, only=None, name='model'):
    os.makedirs(out, exist_ok=True)
    parts, tex, _ = psmdl.parse(open(mdl, 'rb').read())
    blob, _, _ = pstex.decompress(open(mb, 'rb').read())
    base = tex[0][3]
    alpha = set()
    for i, (w, h, fmt, addr) in enumerate(tex):
        o = addr - base
        img = pstex.decode(blob[o:o + pstex.tex_size(w, h, fmt)], w, h, fmt)
        if img.getextrema()[3][0] < 255: alpha.add(i)
        img.save(f'{out}/t{i:02d}.png')
    with open(f'{out}/{name}.mtl', 'w') as m:
        for i in range(len(tex)):
            m.write(f'newmtl t{i:02d}\nKd 1 1 1\nmap_Kd t{i:02d}.png\n' + (f'map_d t{i:02d}.png\n' if i in alpha else '') + '\n')
        m.write('newmtl flat\nKd 0.8 0.8 0.8\n')
    vi = 1; lines = [f'mtllib {name}.mtl']
    for pi, p in enumerate(parts):
        if only is not None and pi not in only: continue
        if not p['mats']: continue
        lines.append(f'o part{pi:02d}')
        for m in p['mats']:
            lines.append('usemtl ' + (f't{m["tex"]:02d}' if m['tex'] < len(tex) else 'flat'))
            for sf, verts in m['strips']:
                for v in verts:
                    lines.append('v %.5f %.5f %.5f' % v[:3])
                    lines.append('vn %.5f %.5f %.5f' % v[3:6])
                    lines.append('vt %.5f %.5f' % (v[6], 1.0 - v[7]))
                for a, b, c in psmdl.strips_to_tris(sf, verts):
                    ok = tri_ok(verts[a], verts[b], verts[c])
                    if ok is None: continue
                    if not ok: b, c = c, b
                    lines.append('f ' + ' '.join(f'{vi + k}/{vi + k}/{vi + k}' for k in (a, b, c)))
                vi += len(verts)
    open(f'{out}/{name}.obj', 'w').write('\n'.join(lines) + '\n')
    return parts, tex

if __name__ == '__main__':
    only = set(int(x) for x in sys.argv[4].split(',')) if len(sys.argv) > 4 else None
    parts, tex = export(sys.argv[1], sys.argv[2], sys.argv[3], only)
    print(len(parts), 'parts', len(tex), 'tex ->', sys.argv[3])
