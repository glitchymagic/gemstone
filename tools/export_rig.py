#!/usr/bin/env python3
"""Fighter form -> rigged GLB: the disc's .MDL parts rigidly skinned to the RAM skeleton (one joint per part,
weight 1), upscaled disc textures, and the RAM-captured motion clips as glTF animations (60 fps).
Usage: export_rig.py X.MDL X_MODEL.BIN skel.json clips_dir out.glb [--texdir dir] [--split 21,22,...]
clips_dir/*.npz from tools/clips.py: q (F, parts, 4) local xyzw quats, t (F, 3) root translation, loop flag.
Parts listed in --split get their own mesh node (head variants, hand poses) so the game can toggle them."""
import argparse, glob, io, json, os, struct, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import psmdl, pstex
from PIL import Image


def build(mdl, mb, skelp, clipdir, out, texdir=None, split=(), root_scale=1.0):
    parts, tex, _ = psmdl.parse(open(mdl, 'rb').read())
    skel = json.load(open(skelp))
    par, off = list(skel['parent']), np.array(skel['offset'], np.float64)
    par_raw = list(skel['parent'])
    n = len(parts)
    par = [p if (p >= 0 or k == 0) else 0 for k, p in enumerate(par)]   # stray roots (hidden parts) hang off the root
    restw = np.zeros((n, 3))
    for k in range(n):          # rest = identity rotations, so world rest is the summed offsets
        c, t = k, np.zeros(3)
        while c >= 0:
            t += off[c]; c = par[c]
        restw[k] = t
    blob, _, _ = pstex.decompress(open(mb, 'rb').read())
    base = tex[0][3]
    imgs = []
    for i, (w, h, fmt, addr) in enumerate(tex):
        p = f'{texdir}/t{i:02d}.png' if texdir else None
        if p and os.path.exists(p):
            imgs.append(Image.open(p).convert('RGBA'))
        else:
            o = addr - base
            imgs.append(pstex.decode(blob[o:o + pstex.tex_size(w, h, fmt)], w, h, fmt))
    bin_ = bytearray(); views = []; accs = []

    def add_view(b, target=None):
        while len(bin_) % 4: bin_.append(0)
        views.append({'buffer': 0, 'byteOffset': len(bin_), 'byteLength': len(b), **({'target': target} if target else {})})
        bin_.extend(b); return len(views) - 1

    def add_acc(arr, typ, comp, target=None, minmax=False):
        v = add_view(np.ascontiguousarray(arr).tobytes(), target)
        a = {'bufferView': v, 'componentType': comp, 'count': len(arr), 'type': typ}
        if minmax: a['min'] = np.min(arr, 0).reshape(-1).tolist(); a['max'] = np.max(arr, 0).reshape(-1).tolist()
        accs.append(a); return len(accs) - 1

    images, textures, materials, matmap = [], [], [], {}

    def material(ti):
        if ti in matmap: return matmap[ti]
        m = {'name': f't{ti:02d}' if ti < len(imgs) else 'flat', 'doubleSided': True,
             'pbrMetallicRoughness': {'metallicFactor': 0.0, 'roughnessFactor': 1.0}}
        if ti < len(imgs):
            bio = io.BytesIO(); imgs[ti].save(bio, 'PNG')
            images.append({'bufferView': add_view(bio.getvalue()), 'mimeType': 'image/png', 'name': f't{ti:02d}'})
            textures.append({'source': len(images) - 1, 'sampler': 0})
            m['pbrMetallicRoughness']['baseColorTexture'] = {'index': len(textures) - 1}
            if imgs[ti].getextrema()[3][0] < 250:
                m['alphaMode'] = 'MASK'; m['alphaCutoff'] = 0.5
        materials.append(m); matmap[ti] = len(materials) - 1; return matmap[ti]

    def mesh_for(pis, name):
        bytex = {}
        for pi in pis:
            for m in parts[pi]['mats']:
                bytex.setdefault(m['tex'], []).append((pi, m))
        prims = []
        for ti, ms in bytex.items():
            P, N, T, J, I = [], [], [], [], []
            for pi, m in ms:
                for sf, verts in m['strips']:
                    b0 = len(P)
                    for v in verts:
                        P.append(np.add(v[:3], restw[pi])); N.append(v[3:6]); T.append(v[6:8]); J.append(pi)
                    for a, b, c in psmdl.strips_to_tris(sf, verts):
                        va, vb, vc = verts[a], verts[b], verts[c]
                        nn = np.cross(np.subtract(vb[:3], va[:3]), np.subtract(vc[:3], va[:3]))
                        if nn @ nn < 1e-12: continue
                        if nn @ (np.add(np.add(va[3:6], vb[3:6]), vc[3:6])) < 0: b, c = c, b
                        I += [b0 + a, b0 + b, b0 + c]
            if not I: continue
            P = np.array(P, np.float32); N = np.array(N, np.float32)
            nl = np.linalg.norm(N, axis=1, keepdims=True)
            N = np.where(nl > 1e-6, N / np.maximum(nl, 1e-6), [0, 1, 0]).astype(np.float32)
            T = np.nan_to_num(np.array(T, np.float32))
            Jn = np.zeros((len(J), 4), np.uint16); Jn[:, 0] = J
            Wt = np.zeros((len(J), 4), np.float32); Wt[:, 0] = 1
            prims.append({'attributes': {'POSITION': add_acc(P, 'VEC3', 5126, 34962, True),
                                         'NORMAL': add_acc(N, 'VEC3', 5126, 34962),
                                         'TEXCOORD_0': add_acc(T, 'VEC2', 5126, 34962),
                                         'JOINTS_0': add_acc(Jn, 'VEC4', 5123, 34962),
                                         'WEIGHTS_0': add_acc(Wt, 'VEC4', 5126, 34962)},
                          'indices': add_acc(np.array(I, np.uint32), 'SCALAR', 5125, 34963), 'material': material(ti)})
        return {'name': name, 'primitives': prims} if prims else None

    nodes = [{'name': f'b{k:02d}', 'translation': off[k].tolist()} for k in range(n)]
    for k in range(n):
        if par[k] >= 0: nodes[par[k]].setdefault('children', []).append(k)
    roots = [k for k in range(n) if par[k] < 0]
    ibm = np.zeros((n, 16), np.float32)
    for k in range(n):
        M = np.eye(4); M[:3, 3] = -restw[k]
        ibm[k] = M.T.reshape(-1)          # column-major
    skins = [{'name': 'skel', 'joints': list(range(n)), 'skeleton': roots[0], 'inverseBindMatrices': add_acc(ibm, 'MAT4', 5126)}]
    meshes = []
    body = [k for k in range(n) if parts[k]['mats'] and k not in split]
    groups = [('body', body)] + [(f'part{k:02d}', [k]) for k in split if parts[k]['mats']]
    scene_nodes = list(roots)
    for name, pis in groups:
        m = mesh_for(pis, name)
        if not m: continue
        meshes.append(m)
        nodes.append({'name': name, 'mesh': len(meshes) - 1, 'skin': 0}); scene_nodes.append(len(nodes) - 1)

    # face / hand variant groups (2 heads on bone 4, 4 right hands on 8, 4 left hands on 12 at the end of the part list):
    # Motion Check only updates the selected variant's matrix, the others keep stale ones, so every variant copies the
    # default variant's pose (they are the same bone, different mesh).
    vgroups = []
    if [par_raw[k] for k in range(n - 10, n)] == [4, 4, 8, 8, 8, 8, 12, 12, 12, 12]:
        vgroups = [[n - 10, n - 9], list(range(n - 8, n - 4)), list(range(n - 4, n))]
    anims = []
    for cp in sorted(glob.glob(os.path.join(clipdir, '*.npz'))) if clipdir else []:
        c = np.load(cp)
        q = c['q'].astype(np.float32); t = (c['t'] * root_scale).astype(np.float32); F = q.shape[0]
        for g in vgroups:
            for k in g[1:]: q[:, k] = q[:, g[0]]
        tin = add_acc((np.arange(F, dtype=np.float32) / 60.0).reshape(-1, 1), 'SCALAR', 5126, None, True)
        samplers, channels = [], []
        for k in range(n):
            samplers.append({'input': tin, 'output': add_acc(q[:, k], 'VEC4', 5126), 'interpolation': 'LINEAR'})
            channels.append({'sampler': len(samplers) - 1, 'target': {'node': k, 'path': 'rotation'}})
        samplers.append({'input': tin, 'output': add_acc(t, 'VEC3', 5126), 'interpolation': 'LINEAR'})
        channels.append({'sampler': len(samplers) - 1, 'target': {'node': roots[0], 'path': 'translation'}})
        if 'free' in c.files:   # parts that leave their bone in this motion get their own translation track
            skip = set(k for g in vgroups for k in g)   # face/hand variants always ride their bone
            for j, k in enumerate(c['free'].tolist()):
                if k < n and k not in skip:
                    samplers.append({'input': tin, 'output': add_acc(np.ascontiguousarray(c['tl'][:, j].astype(np.float32)), 'VEC3', 5126), 'interpolation': 'LINEAR'})
                    channels.append({'sampler': len(samplers) - 1, 'target': {'node': k, 'path': 'translation'}})
        anims.append({'name': os.path.splitext(os.path.basename(cp))[0], 'samplers': samplers, 'channels': channels})

    gl = {'asset': {'version': '2.0', 'generator': 'powerstone-remaster export_rig'},
          'scene': 0, 'scenes': [{'name': os.path.basename(out), 'nodes': scene_nodes}],
          'nodes': nodes, 'meshes': meshes, 'skins': skins, 'materials': materials, 'textures': textures,
          'images': images, 'samplers': [{'magFilter': 9729, 'minFilter': 9987, 'wrapS': 10497, 'wrapT': 10497}],
          'accessors': accs, 'bufferViews': views, 'buffers': [{'byteLength': 0}]}
    if anims: gl['animations'] = anims
    while len(bin_) % 4: bin_.append(0)
    gl['buffers'][0]['byteLength'] = len(bin_)
    js = json.dumps(gl, separators=(',', ':')).encode()
    while len(js) % 4: js += b' '
    with open(out, 'wb') as f:
        f.write(struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(bin_)))
        f.write(struct.pack('<II', len(js), 0x4E4F534A)); f.write(js)
        f.write(struct.pack('<II', len(bin_), 0x004E4942)); f.write(bin_)
    return len(anims)


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('mdl'); ap.add_argument('mb'); ap.add_argument('skel'); ap.add_argument('clips'); ap.add_argument('out')
    ap.add_argument('--texdir'); ap.add_argument('--split', default='')
    ap.add_argument('--root-scale', type=float, default=1.0, help='Power Change forms: the game scales root motion (Falcon 1.05)')
    a = ap.parse_args()
    split = [int(x) for x in a.split.split(',') if x]
    na = build(a.mdl, a.mb, a.skel, a.clips if a.clips != '-' else None, a.out, a.texdir, split, a.root_scale)
    print('wrote', a.out, os.path.getsize(a.out), 'bytes,', na, 'clips')
