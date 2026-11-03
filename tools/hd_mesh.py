#!/usr/bin/env python3
"""Smooth subdivision of the disc's own meshes in a rigged GLB (fighters) or a stage GLB, for the Remaster look.
Phong tessellation (Boubekeur & Alexa 2008): every disc vertex stays exactly where it was (joints between the rigid parts
can't open), new vertices bulge onto the curved surface the disc's own per-vertex normals describe. Edges where the
disc split its normals (hard edges) stay straight lines, so creases stay crisp and the mesh stays watertight; UVs are
interpolated per triangle (seams kept); skin joints/weights are copied from the triangle (each part is rigid on one
joint in these rigs). Images, skins, nodes and every animation clip are passed through untouched.
Usage: hd_mesh.py in.glb out.glb [--seg 4] [--alpha 0.75] [--min-edge 0] [--tex DIR] [--clips X_clips.json]
--seg N: every triangle -> N*N triangles. --min-edge: triangles whose longest edge is shorter than this (model units)
are copied as they are (stages: skip tiny detail).
Remaster extras (all derived from the disc mesh + textures):
--tex DIR: the images are swapped for DIR/tNN.png (hd_tex.py); the Remaster shader loads DIR/tNN_{m,s,n}.png itself.
--clips: the head meshes (variant_groups[0]) get softened face normals: bent toward a sphere centred in the head (the
  centre of the head's skin-coloured vertices) by up to --face (0.35; Look A used 0.85), so the low-poly face shades
  as one clean shape instead of per-polygon blotches.
Every vertex gets COLOR_0 = (ambient occlusion of its own rigid part, ink-line width, face-normal blend, 1). Godot
builds the tangents on import. --ink (Look A, parked): TANGENT = welded normals for the ink hull + masks embedded."""
import argparse, json, os, struct, sys
import numpy as np

CT = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}


def load(fn):
    b = open(fn, 'rb').read()
    l = struct.unpack('<I', b[12:16])[0]
    j = json.loads(b[20:20 + l])
    o = 20 + l
    bl = struct.unpack('<I', b[o:o + 4])[0]
    return j, b[o + 8:o + 8 + bl]


def acc(j, bin_, i):
    a = j['accessors'][i]; v = j['bufferViews'][a['bufferView']]
    dt = CT[a['componentType']]; n = NC[a['type']]
    off = v.get('byteOffset', 0) + a.get('byteOffset', 0)
    stride = v.get('byteStride', 0)
    if stride and stride != n * np.dtype(dt).itemsize:
        raw = np.frombuffer(bin_, np.uint8, stride * a['count'], off).reshape(a['count'], stride)
        arr = raw[:, :n * np.dtype(dt).itemsize].copy().view(dt)
    else:
        arr = np.frombuffer(bin_, dt, a['count'] * n, off).copy()
    if a.get('normalized') and dt != np.float32:
        arr = arr.astype(np.float32) / np.iinfo(dt).max
    return arr.reshape(a['count'], n) if n > 1 else arr


def pattern(S):
    """Barycentric grid of one subdivided triangle: points (u, v, w) and the S*S sub-triangles."""
    pts, idx = [], {}
    for i in range(S + 1):
        for k in range(S + 1 - i):
            idx[(i, k)] = len(pts); pts.append((S - i - k, i, k))
    tris = []
    for i in range(S):
        for k in range(S - i):
            tris.append((idx[(i, k)], idx[(i + 1, k)], idx[(i, k + 1)]))
            if k < S - i - 1:
                tris.append((idx[(i + 1, k)], idx[(i + 1, k + 1)], idx[(i, k + 1)]))
    return np.array(pts, np.float64) / S, np.array(tris, np.int64)


def hard_edges(P, N, J, I, crease_deg=8.0):
    """Per triangle edge (M, 3): True where the disc split its normals across that edge (a hard edge)."""
    # weld by position + joint to find which triangle edges are shared, and whether the disc normals agree there
    key = np.round(P.astype(np.float64), 3)
    jk = J[:, 0].astype(np.float64)[:, None]
    _, pid = np.unique(np.hstack([key, jk]), axis=0, return_inverse=True)
    pid = pid.reshape(-1)
    cosc = np.cos(np.radians(crease_deg))
    edges = {}
    for t, (a, b, c) in enumerate(I):
        for e, (x, y) in enumerate(((a, b), (b, c), (c, a))):
            k = (min(pid[x], pid[y]), max(pid[x], pid[y]))
            edges.setdefault(k, []).append((t, e, x, y))
    flat = np.zeros((len(I), 3), bool)   # per triangle edge: straight (hard edge on the disc)
    for k, lst in edges.items():
        if len(lst) < 2: continue
        hard = False
        for (t1, e1, x1, y1) in lst:
            for (t2, e2, x2, y2) in lst:
                if t1 >= t2: continue
                # match endpoints by position id
                if pid[x1] == pid[x2]: pa, pb = (x1, x2), (y1, y2)
                else: pa, pb = (x1, y2), (y1, x2)
                if N[pa[0]] @ N[pa[1]] < cosc or N[pb[0]] @ N[pb[1]] < cosc:
                    hard = True
        if hard:
            for (t, e, _, _) in lst: flat[t, e] = True
    return flat


def tessellate(P, N, T, J, W, I, S, alpha, min_edge, flat):
    """P/N/T/J/W per vertex, I triangle indices (M, 3), flat = hard_edges(). Returns new arrays."""
    if S <= 1 or len(I) == 0:
        return P, N, T, J, W, I
    bary, sub = pattern(S)
    u, v, w = bary[:, 0:1], bary[:, 1:2], bary[:, 2:3]
    on_e = [(w[:, 0] == 0), (u[:, 0] == 0), (v[:, 0] == 0)]   # edge 0 = a-b (w=0), 1 = b-c (u=0), 2 = c-a (v=0)
    oP, oN, oT, oJ, oW, oI = [], [], [], [], [], []
    base = 0
    for t, (a, b, c) in enumerate(I):
        pa, pb, pc = P[a].astype(np.float64), P[b].astype(np.float64), P[c].astype(np.float64)
        el = max(np.linalg.norm(pa - pb), np.linalg.norm(pb - pc), np.linalg.norm(pc - pa))
        if el < min_edge:
            oP.append(P[[a, b, c]]); oN.append(N[[a, b, c]]); oT.append(T[[a, b, c]]); oJ.append(J[[a, b, c]]); oW.append(W[[a, b, c]])
            oI.append(np.array([[base, base + 1, base + 2]])); base += 3
            continue
        na, nb, nc = N[a].astype(np.float64), N[b].astype(np.float64), N[c].astype(np.float64)
        p = u * pa + v * pb + w * pc
        qa = p - ((p - pa) @ na)[:, None] * na
        qb = p - ((p - pb) @ nb)[:, None] * nb
        qc = p - ((p - pc) @ nc)[:, None] * nc
        ph = (1 - alpha) * p + alpha * (u * qa + v * qb + w * qc)
        for e in range(3):
            if flat[t, e]: ph[on_e[e]] = p[on_e[e]]
        n = u * na + v * nb + w * nc
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
        uv = u * T[a] + v * T[b] + w * T[c]
        oP.append(ph.astype(np.float32)); oN.append(n.astype(np.float32)); oT.append(uv.astype(np.float32))
        oJ.append(np.repeat(J[a:a + 1], len(bary), 0)); oW.append(np.repeat(W[a:a + 1], len(bary), 0))
        oI.append(sub + base); base += len(bary)
    return (np.concatenate(oP), np.concatenate(oN), np.concatenate(oT), np.concatenate(oJ), np.concatenate(oW),
            np.concatenate(oI))


def fib_dirs(k):
    """k unit directions, cosine-weighted around +z (Fibonacci spiral)."""
    i = np.arange(k) + 0.5
    r = np.sqrt(i / k); phi = i * np.pi * (3 - np.sqrt(5))
    return np.stack([r * np.cos(phi), r * np.sin(phi), np.sqrt(1 - r * r)], -1)


def ray_ao(P, N, tris, max_d, k=24):
    """Fraction of k cosine-weighted rays from each point (offset along N) that miss tris (T, 3, 3) within max_d."""
    d0 = fib_dirs(k)
    up = np.where(np.abs(N[:, 2:3]) < 0.9, np.array([[0, 0, 1.0]]), np.array([[1.0, 0, 0]]))
    t1 = np.cross(up, N); t1 /= np.maximum(np.linalg.norm(t1, axis=1, keepdims=True), 1e-9)
    t2 = np.cross(N, t1)
    D = d0[None, :, 0:1] * t1[:, None] + d0[None, :, 1:2] * t2[:, None] + d0[None, :, 2:3] * N[:, None]   # (n, k, 3)
    O = (P + N * max_d * 0.01)[:, None, :].repeat(k, 1)
    O = O.reshape(-1, 3); D = D.reshape(-1, 3)
    hit = np.zeros(len(O), bool)
    v0, e1, e2 = tris[:, 0], tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0]
    for c in range(0, len(O), 4096):
        o, d = O[c:c + 4096, None], D[c:c + 4096, None]
        pv = np.cross(d, e2[None]); det = (e1[None] * pv).sum(-1)
        ok = np.abs(det) > 1e-9; inv = 1.0 / np.where(ok, det, 1.0)
        tv = o - v0[None]; u = (tv * pv).sum(-1) * inv
        qv = np.cross(tv, e1[None]); v = (d * qv).sum(-1) * inv
        t = (e2[None] * qv).sum(-1) * inv
        h = ok & (u >= 0) & (v >= 0) & (u + v <= 1) & (t > 1e-4) & (t < max_d)
        hit[c:c + 4096] = h.any(1)
    return 1.0 - hit.reshape(-1, k).mean(1)


def weld_normals(P, N, J):
    """Normals averaged over vertices at the same position on the same joint (hard edges smoothed)."""
    key = np.hstack([np.round(P.astype(np.float64), 3), J[:, :1].astype(np.float64)])
    _, inv = np.unique(key, axis=0, return_inverse=True); inv = inv.reshape(-1)
    acc_ = np.zeros((inv.max() + 1, 3)); np.add.at(acc_, inv, N.astype(np.float64))
    out = acc_[inv]
    return (out / np.maximum(np.linalg.norm(out, axis=1, keepdims=True), 1e-9)).astype(np.float32)


class Masks:
    """Class weights at a UV of a material's texture (tNN_m.png: R skin, G hair)."""
    def __init__(self, d):
        self.d = d; self.c = {}

    def at(self, name, uv):
        if name not in self.c:
            from PIL import Image
            f = os.path.join(self.d, name + '_m.png') if self.d else ''
            self.c[name] = np.asarray(Image.open(f)).astype(np.float32) / 255.0 if f and os.path.exists(f) else None
        m = self.c[name]
        if m is None: return np.zeros((len(uv), 4), np.float32)
        h, w = m.shape[:2]
        x = (np.mod(uv[:, 0], 1.0) * w).astype(int).clip(0, w - 1); y = (np.mod(uv[:, 1], 1.0) * h).astype(int).clip(0, h - 1)
        return m[y, x]


def remaster_attrs(meshdata, head, masks, matname, face=0.85):
    """meshdata: list of [P, N, T, J, W, I, material] per primitive of one mesh (after tessellation); edits N in place
    for heads and returns per primitive (COLOR_0, TANGENT)."""
    allP = np.concatenate([d[0] for d in meshdata]); allJ = np.concatenate([d[3] for d in meshdata])
    cls = [masks.at(matname(d[6]), d[2]) for d in meshdata]
    if head:
        sk = np.concatenate([c[:, 0] for c in cls]); hr = np.concatenate([c[:, 1] for c in cls])
        sel = sk > 0.5
        lo, hi = allP.min(0), allP.max(0)
        c_all = (lo + hi) * 0.5
        c_skin = (allP[sel].min(0) + allP[sel].max(0)) * 0.5 if sel.sum() > 20 else c_all
        ctr = c_skin * 0.6 + c_all * 0.4
    out = []
    for d, c in zip(meshdata, cls):
        P, N, T, J, W, I, _ = d
        col = np.ones((len(P), 4), np.float32)
        if head:
            k = (np.clip(0.3 + 0.55 * c[:, 0] + 0.3 * c[:, 1], 0, 0.85) * (face / 0.85))[:, None]
            s = P - ctr; s /= np.maximum(np.linalg.norm(s, axis=1, keepdims=True), 1e-9)
            n = N * (1 - k) + s * k
            d[1] = (n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)).astype(np.float32)
            col[:, 2] = k[:, 0]
        else:
            col[:, 2] = 0.0
        out.append(col)
    # ambient occlusion + ink width per rigid part (one joint each), occluded only by its own part
    allN = np.concatenate([d[1] for d in meshdata]); allI = []
    off = 0
    for d in meshdata: allI.append(d[5] + off); off += len(d[0])
    allI = np.concatenate(allI)
    ao = np.ones(len(allP), np.float32); width = np.ones(len(allP), np.float32)
    for j in np.unique(allJ[:, 0]):
        vs = np.where(allJ[:, 0] == j)[0]
        ts = allI[(allJ[allI[:, 0], 0] == j)]
        if len(vs) == 0 or len(ts) == 0: continue
        size = np.linalg.norm(allP[vs].max(0) - allP[vs].min(0))
        # occluders: a coarse copy (every 4th sub-triangle keeps the shape, x16 fewer tests)
        occ = allP[ts[::4]].astype(np.float64)
        ao[vs] = ray_ao(allP[vs].astype(np.float64), allN[vs].astype(np.float64), occ, max(size * 0.35, 1e-3))
        width[vs] = np.clip(size / 45.0, 0.55, 1.15)
    tan = []
    off = 0
    welded = weld_normals(allP, allN, allJ)
    for d, col in zip(meshdata, out):
        n = len(d[0])
        col[:, 0] = ao[off:off + n]
        col[:, 1] = width[off:off + n] * np.where(col[:, 2] > 0.5, 0.7, 1.0)   # thinner lines across the face
        tan.append(np.hstack([welded[off:off + n], np.ones((n, 1), np.float32)]))
        off += n
    return out, tan


def swap_images(j, out_bytes, views, tex_dir, masks=False):
    """Images -> tex_dir/<name>.png; every textured material gets its _m (metallicRoughness) and _s (occlusion) maps."""
    def add_png(path, name):
        b = open(path, 'rb').read()
        while len(out_bytes) % 4: out_bytes.append(0)
        views.append({'buffer': 0, 'byteOffset': len(out_bytes), 'byteLength': len(b)}); out_bytes.extend(b)
        j['images'].append({'bufferView': len(views) - 1, 'mimeType': 'image/png', 'name': name})
        j['textures'].append({'source': len(j['images']) - 1, 'sampler': 0})
        return len(j['textures']) - 1
    for im in list(j.get('images', [])):
        f = os.path.join(tex_dir, im['name'] + '.png')
        if not os.path.exists(f): continue
        b = open(f, 'rb').read()
        while len(out_bytes) % 4: out_bytes.append(0)
        views.append({'buffer': 0, 'byteOffset': len(out_bytes), 'byteLength': len(b)}); out_bytes.extend(b)
        im['bufferView'] = len(views) - 1
    for m in j.get('materials', []):
        bt = m.get('pbrMetallicRoughness', {}).get('baseColorTexture')
        if not bt: continue
        name = j['images'][j['textures'][bt['index']]['source']]['name']
        fm, fs = os.path.join(tex_dir, name + '_m.png'), os.path.join(tex_dir, name + '_s.png')
        if masks and os.path.exists(fm) and os.path.exists(fs):
            m['pbrMetallicRoughness']['metallicRoughnessTexture'] = {'index': add_png(fm, name + '_m')}
            m['occlusionTexture'] = {'index': add_png(fs, name + '_s')}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('src'); ap.add_argument('dst')
    ap.add_argument('--seg', type=int, default=4)
    ap.add_argument('--alpha', type=float, default=0.75)
    ap.add_argument('--min-edge', type=float, default=0.0)
    ap.add_argument('--tex', default='')
    ap.add_argument('--clips', default='')
    ap.add_argument('--face', type=float, default=0.35, help='head normal bend toward the head sphere (anime: 0.85)')
    ap.add_argument('--ink', action='store_true', help='Look A (parked): TANGENT = welded normals for the ink hull, '
                    'masks embedded as material textures')
    a = ap.parse_args()
    j, bin_ = load(a.src)
    out = bytearray(); views = []; accs = []

    def add(arr, typ, comp, target=None, minmax=False):
        while len(out) % 4: out.append(0)
        b = np.ascontiguousarray(arr).tobytes()
        views.append({'buffer': 0, 'byteOffset': len(out), 'byteLength': len(b), **({'target': target} if target else {})})
        out.extend(b)
        acc_ = {'bufferView': len(views) - 1, 'componentType': comp, 'count': len(arr), 'type': typ}
        if minmax: acc_['min'] = np.min(arr, 0).tolist(); acc_['max'] = np.max(arr, 0).tolist()
        accs.append(acc_); return len(accs) - 1

    # copy every accessor that is not a mesh attribute/index (animations, skins, images live in buffer views)
    mesh_accs = set()
    for m in j.get('meshes', []):
        for p in m['primitives']:
            mesh_accs.update(p['attributes'].values())
            if 'indices' in p: mesh_accs.add(p['indices'])
    remap_view = {}
    for vi, v in enumerate(j['bufferViews']):
        used_by_mesh_only = all(ai in mesh_accs for ai, x in enumerate(j['accessors']) if x.get('bufferView') == vi) and \
            any(x.get('bufferView') == vi for x in j['accessors'])
        if used_by_mesh_only: continue
        while len(out) % 4: out.append(0)
        o = v.get('byteOffset', 0)
        nv = dict(v); nv['byteOffset'] = len(out)
        out.extend(bin_[o:o + v['byteLength']])
        views.append(nv); remap_view[vi] = len(views) - 1
    acc_map = {}
    for ai, x in enumerate(j['accessors']):
        if ai in mesh_accs: continue
        nx = dict(x)
        if 'bufferView' in x: nx['bufferView'] = remap_view[x['bufferView']]
        accs.append(nx); acc_map[ai] = len(accs) - 1
    for im in j.get('images', []):
        if 'bufferView' in im: im['bufferView'] = remap_view[im['bufferView']]
    for s in j.get('skins', []):
        if 'inverseBindMatrices' in s: s['inverseBindMatrices'] = acc_map[s['inverseBindMatrices']]
    for an in j.get('animations', []):
        for sm in an['samplers']:
            sm['input'] = acc_map[sm['input']]; sm['output'] = acc_map[sm['output']]
    remaster = bool(a.tex)
    heads = set(json.load(open(a.clips)).get('variant_groups', [[]])[0]) if a.clips and os.path.exists(a.clips) else set()
    masks = Masks(a.tex)
    def matname(mi):
        if mi is None: return ''
        bt = j['materials'][mi].get('pbrMetallicRoughness', {}).get('baseColorTexture')
        return j['images'][j['textures'][bt['index']]['source']]['name'] if bt else ''
    tin = tout = 0
    for m in j.get('meshes', []):
        # hard edges are found across all of a mesh's primitives (texture borders), then each primitive is split
        data = []
        for p in m['primitives']:
            at = p['attributes']
            P = acc(j, bin_, at['POSITION']).astype(np.float32)
            N = acc(j, bin_, at['NORMAL']).astype(np.float32) if 'NORMAL' in at else np.tile([0, 1, 0], (len(P), 1)).astype(np.float32)
            T = acc(j, bin_, at['TEXCOORD_0']).astype(np.float32) if 'TEXCOORD_0' in at else np.zeros((len(P), 2), np.float32)
            J = acc(j, bin_, at['JOINTS_0']).astype(np.uint16) if 'JOINTS_0' in at else np.zeros((len(P), 4), np.uint16)
            W = acc(j, bin_, at['WEIGHTS_0']).astype(np.float32) if 'WEIGHTS_0' in at else np.zeros((len(P), 4), np.float32)
            I = acc(j, bin_, p['indices']).astype(np.int64).reshape(-1, 3) if 'indices' in p else np.arange(len(P)).reshape(-1, 3)
            data.append((p, at, P, N, T, J, W, I))
        off = np.cumsum([0] + [len(d[2]) for d in data])
        allI = np.concatenate([d[7] + off[k] for k, d in enumerate(data)]) if data else np.zeros((0, 3), np.int64)
        flat = hard_edges(np.concatenate([d[2] for d in data]), np.concatenate([d[3] for d in data]),
                          np.concatenate([d[5] for d in data]), allI) if data else None
        toff = np.cumsum([0] + [len(d[7]) for d in data])
        tess = []
        for k, (p, at, P, N, T, J, W, I) in enumerate(data):
            tin += len(I)
            P, N, T, J, W, I = tessellate(P, N, T, J, W, I, a.seg, a.alpha, a.min_edge, flat[toff[k]:toff[k + 1]])
            tout += len(I)
            tess.append([P, N, T, J, W, I, p.get('material')])
        cols = tans = None
        if remaster and tess:
            cols, tans = remaster_attrs(tess, m.get('name') in heads, masks, matname, a.face)
        for k, (p, at, *_r) in enumerate(data):
            P, N, T, J, W, I, _ = tess[k]
            na = {'POSITION': add(P, 'VEC3', 5126, 34962, True), 'NORMAL': add(N, 'VEC3', 5126, 34962),
                  'TEXCOORD_0': add(T, 'VEC2', 5126, 34962)}
            if cols is not None:
                na['COLOR_0'] = add(cols[k], 'VEC4', 5126, 34962)
                if a.ink: na['TANGENT'] = add(tans[k], 'VEC4', 5126, 34962)   # else Godot builds real tangents
            if 'JOINTS_0' in at:
                na['JOINTS_0'] = add(J, 'VEC4', 5123, 34962); na['WEIGHTS_0'] = add(W, 'VEC4', 5126, 34962)
            p['attributes'] = na
            p['indices'] = add(I.astype(np.uint32).reshape(-1), 'SCALAR', 5125, 34963)
    if remaster: swap_images(j, out, views, a.tex, a.ink)
    j['bufferViews'] = views; j['accessors'] = accs
    j['buffers'] = [{'byteLength': len(out)}]
    js = json.dumps(j, separators=(',', ':')).encode()
    while len(js) % 4: js += b' '
    while len(out) % 4: out.append(0)
    os.makedirs(os.path.dirname(os.path.abspath(a.dst)), exist_ok=True)
    with open(a.dst, 'wb') as f:
        f.write(struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(out)))
        f.write(struct.pack('<II', len(js), 0x4E4F534A)); f.write(js)
        f.write(struct.pack('<II', len(out), 0x004E4942)); f.write(out)
    print(f'{os.path.basename(a.src)}: {tin} -> {tout} triangles -> {a.dst}')


if __name__ == '__main__':
    main()
