#!/usr/bin/env python3
"""Material classes for the Remaster look, per texel of the disc's own textures: skin, hair, metal, leather, gem,
eyes, cloth (the rest). Authored per fighter form as reference colours in tools/hd_classes.json (picked from a palette
of the form's own texture colours), plus per-texture overrides; every texel gets soft weights from its nearest
references (Lab distance), so class borders follow the texture's own colour borders.
Usage:
  hd_classes.py palette ID out.png    k-means palette of form ID (p00 ...) with hex codes + where each colour lives
  hd_classes.py show ID out.png       the class map of every texture next to the texture (authoring check)
The texture source is the disc decode (hd_tex.originals)."""
import json, os, sys
import numpy as np
from PIL import Image, ImageDraw
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hd_tex

CLASSES = ['cloth', 'skin', 'hair', 'metal', 'leather', 'gem', 'eyes']
CFG = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'hd_classes.json')
SHOW = {'cloth': (90, 90, 90), 'skin': (255, 170, 140), 'hair': (240, 220, 40), 'metal': (80, 200, 255),
        'leather': (150, 80, 30), 'gem': (255, 40, 220), 'eyes': (40, 255, 80)}


def lab(rgb):
    """sRGB 0..1 (..., 3) -> CIE Lab."""
    c = np.where(rgb > 0.04045, ((rgb + 0.055) / 1.055) ** 2.4, rgb / 12.92)
    M = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    xyz = c @ M.T / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)


def hexc(c):
    return '%02x%02x%02x' % tuple(int(x) for x in c)


def unhex(h):
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], np.float64)


def config(fid):
    j = json.load(open(CFG)) if os.path.exists(CFG) else {}
    c = j.get(fid.lower(), {})
    if 'like' in c:   # a form that shares another form's colours (2P palettes, Power Change forms with the same suit)
        base = dict(j.get(c['like'], {})); base.update({k: v for k, v in c.items() if k != 'like'}); c = base
    return c


def weights(im, cfg, tex_name='', head=False, sigma=9.0, far=24.0):
    """RGBA image -> (H, W, 7) class weights (CLASSES order), soft by Lab distance to the authored references."""
    a = np.asarray(im.convert('RGBA')).astype(np.float64) / 255.0
    H, W = a.shape[:2]
    ov = cfg.get('tex', {}).get(tex_name)
    out = np.zeros((H, W, len(CLASSES)))
    if isinstance(ov, str):   # the whole texture is one class
        out[..., CLASSES.index(ov)] = 1.0
        return out
    if head and cfg.get('eyes') and not isinstance(ov, dict):   # eye colours only count on the face textures
        head = weights(im, cfg, tex_name, False, sigma, far)[..., 1][a[..., 3] > 0.5].mean() > 0.3
    no_hair = False
    if not head and cfg.get('hair') and not isinstance(ov, dict) and sigma > 0:   # hair colours off the head only
        no_hair = weights(im, cfg, tex_name, True, -sigma, far)[..., 2][a[..., 3] > 0.5].mean() < 0.35   # on hair parts
    sigma = abs(sigma)
    refs, rc = [], []
    for k in CLASSES:
        for h in cfg.get(k, []):
            if k in ('eyes',) and not head: continue
            if k == 'hair' and no_hair: continue
            refs.append(unhex(h) / 255.0); rc.append(CLASSES.index(k))
    if isinstance(ov, dict):   # per-texture extra references {"metal": ["c0c0c0"], ...}
        for k, hs in ov.items():
            for h in hs: refs.append(unhex(h) / 255.0); rc.append(CLASSES.index(k))
    if not refs:
        out[..., 0] = 1.0
        return out
    refs.append(np.zeros(3)); rc.append(0)   # far from every reference: cloth
    L = lab(a[..., :3])
    R = lab(np.array(refs))
    d2 = ((L[:, :, None, :] - R[None, None]) ** 2).sum(-1)
    d2[..., -1] = far * far
    d2 -= d2.min(-1, keepdims=True)
    w = np.exp(-d2 / (2 * sigma * sigma))
    w /= w.sum(-1, keepdims=True)
    for i, c in enumerate(rc): out[..., c] += w[..., i]
    return out


def head_textures(fid):
    """Texture names (tNN) used by the head variant meshes of a ripped fighter GLB (clips.json variant_groups[0])."""
    import hd_mesh
    here = os.path.dirname(os.path.abspath(__file__))
    glb = os.path.join(here, '..', 'game', 'assets', 'ripped', fid.lower() + '.glb')
    cj = glb[:-4] + '_clips.json'
    if not os.path.exists(glb): return set()
    j, _ = hd_mesh.load(glb)
    heads = set(json.load(open(cj)).get('variant_groups', [[]])[0]) if os.path.exists(cj) else set()
    out = set()
    for m in j['meshes']:
        if m.get('name') in heads:
            for p in m['primitives']:
                if 'material' in p: out.add(j['materials'][p['material']]['name'])
    return out


def palette(fid, path, k=16):
    from scipy.cluster.vq import kmeans2
    texs = hd_tex.originals(fid)
    px, src = [], []
    for i, t in enumerate(texs):
        a = np.asarray(t.convert('RGBA')).reshape(-1, 4)
        a = a[a[:, 3] > 127][:, :3]
        px.append(a); src.append(np.full(len(a), i))
    px = np.concatenate(px).astype(np.float64); src = np.concatenate(src)
    P = lab(px / 255.0)
    cent, lbl = kmeans2(P, k, minit='++', seed=0)
    near = lambda q: ((q[:, None, :] - cent[None]) ** 2).sum(-1).argmin(1)
    order = np.argsort(-np.bincount(lbl, minlength=k))
    S = 64
    im = Image.new('RGB', (S * 6 + 120, len(order) * (S + 4)), (30, 30, 30)); d = ImageDraw.Draw(im)
    for r, c in enumerate(order):
        sel = lbl == c
        mean = px[sel].mean(0)
        y = r * (S + 4)
        d.rectangle([0, y, S, y + S], fill=tuple(int(x) for x in mean))
        d.text((S + 4, y + 4), hexc(mean), fill=(255, 255, 0)); d.text((S + 4, y + 20), '%d' % sel.sum(), fill=(200, 200, 200))
        top = np.argsort(-np.bincount(src[sel], minlength=len(texs)))[:4]
        for q, ti in enumerate(top):
            if not (src[sel] == ti).any(): continue
            t = texs[ti].convert('RGBA')
            a = np.asarray(t).copy()
            m = (near(lab(a[..., :3].reshape(-1, 3) / 255.0)) == c).reshape(a.shape[:2])
            a[~m] = (a[~m] * 0.25).astype(np.uint8); a[..., 3] = 255
            th = Image.fromarray(a).resize((S, S), Image.NEAREST)
            x = 120 + S + q * (S + 4)
            im.paste(th, (x, y)); d.text((x + 2, y + 2), 't%02d' % ti, fill=(255, 255, 255))
    im.save(path)
    print('palette', fid, '->', path)


def show(fid, path):
    cfg = config(fid)
    heads = head_textures(fid)
    texs = hd_tex.originals(fid)
    S, C = 64, 8
    R = (len(texs) + C - 1) // C
    im = Image.new('RGB', (C * (2 * S + 6), R * (S + 14)), (30, 30, 30)); d = ImageDraw.Draw(im)
    pal = np.array([SHOW[c] for c in CLASSES], np.float64)
    for i, t in enumerate(texs):
        w = weights(t, cfg, 't%02d' % i, 't%02d' % i in heads)
        cm = (w @ pal).astype(np.uint8)
        x, y = (i % C) * (2 * S + 6), (i // C) * (S + 14)
        im.paste(t.convert('RGB').resize((S, S), Image.NEAREST), (x, y + 14))
        im.paste(Image.fromarray(cm).resize((S, S), Image.NEAREST), (x + S, y + 14))
        d.text((x, y), 't%02d%s' % (i, ' H' if 't%02d' % i in heads else ''), fill=(255, 255, 0))
    im.save(path)
    print('classes', fid, '->', path)


if __name__ == '__main__':
    {'palette': palette, 'show': show}[sys.argv[1]](sys.argv[2], sys.argv[3])
