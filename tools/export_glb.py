#!/usr/bin/env python3
"""MDL + MODEL.BIN -> GLB (one node+mesh per part, textures embedded as PNG).
Usage: export_glb.py X.MDL X_MODEL.BIN out.glb [--skel skel.json] [--parts 0,1,3] [--texdir dir]
skel.json: {"parent":[...], "offset":[[x,y,z],...]} per part index (optional; flat at origin otherwise).
--texdir: use dir/tNN.png (e.g. upscaled) instead of the decoded originals."""
import argparse, io, json, os, struct, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import psmdl, pstex
from PIL import Image

def build(mdl, mb, out, skel=None, only=None, texdir=None, name=None):
    parts, tex, _ = psmdl.parse(open(mdl, 'rb').read())
    blob, _, _ = pstex.decompress(open(mb, 'rb').read())
    base = tex[0][3]
    imgs = []
    for i, (w, h, fmt, addr) in enumerate(tex):
        if texdir and os.path.exists(f'{texdir}/t{i:02d}.png'):
            im = Image.open(f'{texdir}/t{i:02d}.png').convert('RGBA')
        else:
            o = addr - base
            im = pstex.decode(blob[o:o + pstex.tex_size(w, h, fmt)], w, h, fmt)
        imgs.append(im)
    bin_ = bytearray(); views = []; accs = []
    def add_view(b, target=None):
        while len(bin_) % 4: bin_.append(0)
        views.append({'buffer': 0, 'byteOffset': len(bin_), 'byteLength': len(b), **({'target': target} if target else {})})
        bin_.extend(b); return len(views) - 1
    def add_acc(arr, typ, comp, target, minmax=False):
        v = add_view(arr.tobytes(), target)
        a = {'bufferView': v, 'componentType': comp, 'count': len(arr), 'type': typ}
        if minmax: a['min'] = arr.min(0).tolist(); a['max'] = arr.max(0).tolist()
        accs.append(a); return len(accs) - 1
    images = []; textures = []; materials = []; matmap = {}
    semi = {}
    def blend_of(m):
        # PowerVR TA words: PCW bits 24-26 = list type (2 = translucent); TSP bits 31-29 / 28-26 = src / dst blend
        # instruction (4 = SRC_ALPHA, 1 = ONE, 5 = INV_SRC_ALPHA). Translucent + dst ONE = additive (light shafts,
        # glows; order-independent). SRC_ALPHA / INV_SRC_ALPHA becomes a real blend only when the texture's alpha is
        # really partial (the hardware sorts translucency per pixel, Godot per object: on/off alpha stays a cut-out)
        if (m['pcw'] >> 24) & 7 != 2: return ''
        if (m['tsp'] >> 26) & 7 == 1: return '_add'
        ti = m['tex']
        if ti not in semi:
            a = np.asarray(imgs[ti])[..., 3] if ti < len(imgs) else np.full(1, 255)
            semi[ti] = float(((a > 24) & (a < 232)).mean()) > 0.02
        return '_blend' if semi[ti] else ''
    def material(ti, bl=''):
        if (ti, bl) in matmap: return matmap[(ti, bl)]
        m = {'name': (f't{ti:02d}' if ti < len(imgs) else 'flat') + bl, 'doubleSided': True,
             'pbrMetallicRoughness': {'metallicFactor': 0.0, 'roughnessFactor': 1.0}}
        if ti < len(imgs):
            bio = io.BytesIO(); imgs[ti].save(bio, 'PNG')
            images.append({'bufferView': add_view(bio.getvalue()), 'mimeType': 'image/png', 'name': f't{ti:02d}'})
            textures.append({'source': len(images) - 1, 'sampler': 0})
            m['pbrMetallicRoughness']['baseColorTexture'] = {'index': len(textures) - 1}
            if bl:
                m['alphaMode'] = 'BLEND'
            elif imgs[ti].getextrema()[3][0] < 250:
                m['alphaMode'] = 'MASK'; m['alphaCutoff'] = 0.5
        elif bl:
            m['alphaMode'] = 'BLEND'
        materials.append(m); matmap[(ti, bl)] = len(materials) - 1; return matmap[(ti, bl)]
    meshes = []; nodes = []; part_node = {}
    for pi, p in enumerate(parts):
        node = {'name': f'part{pi:02d}'}
        if skel: node['translation'] = list(map(float, skel['offset'][pi]))
        if p['mats'] and (only is None or pi in only):
            bytex = {}
            for m in p['mats']:
                bytex.setdefault((m['tex'], blend_of(m)), []).append(m)
            prims = []
            for (ti, bl), ms in bytex.items():
                P = []; N = []; T = []; I = []
                for m in ms:
                    for sf, verts in m['strips']:
                        b0 = len(P)
                        for v in verts: P.append(v[:3]); N.append(v[3:6]); T.append(v[6:8])
                        for a, b, c in psmdl.strips_to_tris(sf, verts):
                            va, vb, vc = verts[a], verts[b], verts[c]
                            e1 = np.subtract(vb[:3], va[:3]); e2 = np.subtract(vc[:3], va[:3])
                            n = np.cross(e1, e2)
                            if n @ n < 1e-12: continue
                            if n @ (np.add(np.add(va[3:6], vb[3:6]), vc[3:6])) < 0: b, c = c, b
                            I += [b0 + a, b0 + b, b0 + c]
                if not I: continue
                P = np.array(P, np.float32); N = np.array(N, np.float32)
                nl = np.linalg.norm(N, axis=1, keepdims=True); N = np.where(nl > 1e-6, N / np.maximum(nl, 1e-6), [0, 1, 0]).astype(np.float32)
                T = np.nan_to_num(np.array(T, np.float32)); I = np.array(I, np.uint32)
                prims.append({'attributes': {'POSITION': add_acc(P, 'VEC3', 5126, 34962, True),
                                             'NORMAL': add_acc(N, 'VEC3', 5126, 34962),
                                             'TEXCOORD_0': add_acc(T, 'VEC2', 5126, 34962)},
                              'indices': add_acc(I, 'SCALAR', 5125, 34963), 'material': material(ti, bl)})
            if prims:
                meshes.append({'name': f'part{pi:02d}', 'primitives': prims}); node['mesh'] = len(meshes) - 1
        nodes.append(node); part_node[pi] = len(nodes) - 1
    roots = []
    for pi in range(len(parts)):
        par = skel['parent'][pi] if skel else -1
        if par is None or par < 0: roots.append(part_node[pi])
        else: nodes[part_node[par]].setdefault('children', []).append(part_node[pi])
    gl = {'asset': {'version': '2.0', 'generator': 'powerstone-remaster export_glb'},
          'scene': 0, 'scenes': [{'name': name or os.path.basename(out), 'nodes': roots}],
          'nodes': nodes, 'meshes': meshes, 'materials': materials, 'textures': textures, 'images': images,
          'samplers': [{'magFilter': 9729, 'minFilter': 9987, 'wrapS': 10497, 'wrapT': 10497}],
          'accessors': accs, 'bufferViews': views, 'buffers': [{'byteLength': len(bin_)}]}
    js = json.dumps(gl, separators=(',', ':')).encode()
    while len(js) % 4: js += b' '
    while len(bin_) % 4: bin_.append(0)
    with open(out, 'wb') as f:
        f.write(struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(bin_)))
        f.write(struct.pack('<II', len(js), 0x4E4F534A)); f.write(js)
        f.write(struct.pack('<II', len(bin_), 0x004E4942)); f.write(bin_)
    return parts, tex

if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('mdl'); ap.add_argument('mb'); ap.add_argument('out')
    ap.add_argument('--skel'); ap.add_argument('--parts'); ap.add_argument('--texdir')
    a = ap.parse_args()
    skel = json.load(open(a.skel)) if a.skel else None
    only = set(map(int, a.parts.split(','))) if a.parts else None
    parts, tex = build(a.mdl, a.mb, a.out, skel, only, a.texdir)
    print('wrote', a.out, os.path.getsize(a.out), 'bytes', len(parts), 'parts')
