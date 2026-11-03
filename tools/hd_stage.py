#!/usr/bin/env python3
"""Remaster stage materials: a material class per stage texture (stone, wood, metal, water, glass, foliage, ground,
cloth, painted), guessed from the disc texture itself (colour, alpha cut-outs, grain direction, edge density) plus
hand overrides in game/assets/remaster/stage_classes.json ("overrides": {"stg00_world_t01": "stone"}). The stage shader
(game/shaders/stage_pbr.gdshader) turns the class into roughness / metal / normal strength / parallax / wind sway.
Usage:
  hd_stage.py classify            -> writes the "auto" table into stage_classes.json (overrides kept)
  hd_stage.py show stg00 out.png  -> contact sheet of a stage's textures with their final class (authoring check)
Textures: game/assets/ripped/stgN0_*_tNN.png (the 4x textures the stage GLBs carry)."""
import glob, json, os, sys
import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
RIPPED = os.path.join(HERE, '..', 'game', 'assets', 'ripped')
CFG = os.path.join(HERE, '..', 'game', 'assets', 'remaster', 'stage_classes.json')
CLASSES = ['painted', 'stone', 'wood', 'metal', 'water', 'glass', 'foliage', 'ground', 'cloth', 'snow']
SHOW = {'painted': (120, 120, 120), 'stone': (200, 190, 170), 'wood': (160, 90, 30), 'metal': (80, 200, 255),
        'water': (30, 90, 255), 'glass': (180, 255, 255), 'foliage': (40, 220, 60), 'ground': (120, 80, 50),
        'cloth': (255, 80, 160), 'snow': (255, 255, 255)}


def hsv(rgb):
    mx, mn = rgb.max(-1), rgb.min(-1)
    d = mx - mn
    h = np.zeros_like(mx)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    m = d > 1e-6
    hr = (mx == r) & m; hg = (mx == g) & m & ~hr; hb = m & ~hr & ~hg
    h[hr] = ((g - b)[hr] / d[hr]) % 6
    h[hg] = (b - r)[hg] / d[hg] + 2
    h[hb] = (r - g)[hb] / d[hb] + 4
    return h / 6.0, np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0), mx


def features(path):
    a = np.asarray(Image.open(path).convert('RGBA').resize((128, 128), Image.BILINEAR)).astype(np.float32) / 255.0
    op = a[..., 3] > 0.5
    rgb = a[..., :3]
    h, s, v = hsv(rgb)
    lum = rgb @ np.array([0.299, 0.587, 0.114], np.float32)
    gx = np.roll(lum, -1, 1) - np.roll(lum, 1, 1); gy = np.roll(lum, -1, 0) - np.roll(lum, 1, 0)
    sel = op if op.sum() > 50 else np.ones_like(op)
    jxx, jyy, jxy = (gx * gx)[sel].mean(), (gy * gy)[sel].mean(), (gx * gy)[sel].mean()
    coh = np.sqrt((jxx - jyy) ** 2 + 4 * jxy ** 2) / max(jxx + jyy, 1e-9)   # 1 = one grain direction
    f = lambda m: float((m & sel).sum() / max(sel.sum(), 1))
    return {
        'cut': float(1 - op.mean()),
        'green': f((h > 0.17) & (h < 0.45) & (s > 0.25) & (v > 0.12)),
        'blue': f((h > 0.42) & (h < 0.7) & (s > 0.25)),
        'beige': f((h > 0.02) & (h < 0.17) & (s < 0.4) & (v > 0.2)),
        'brown': f((h > 0.02) & (h < 0.13) & (s > 0.22) & (s < 0.85) & (v > 0.12) & (v < 0.8)),
        'grey': f(s < 0.16),
        'sat': float(s[sel].mean()), 'val': float(v[sel].mean()),
        'edge': float(np.sqrt(gx * gx + gy * gy)[sel].mean()),
        'coh': float(coh),
    }


def guess(ft):
    if ft['cut'] > 0.06 and ft['green'] > 0.25: return 'foliage'
    if ft['green'] > 0.55 and ft['edge'] > 0.05: return 'foliage'
    if ft['brown'] > 0.45 and ft['coh'] > 0.3: return 'wood'
    if max(ft['grey'], ft['beige']) + 0.5 * ft['brown'] > 0.6 and ft['edge'] > 0.03: return 'stone'
    if ft['brown'] > 0.5 and ft['edge'] <= 0.045: return 'ground'
    if ft['sat'] > 0.5: return 'cloth' if ft['edge'] < 0.04 else 'painted'
    return 'stone' if ft['grey'] > 0.4 else 'painted'


def load():
    return json.load(open(CFG)) if os.path.exists(CFG) else {'_doc': __doc__.split('\n')[0], 'overrides': {}, 'auto': {}}


def classify():
    j = load()
    j['auto'] = {}
    for p in sorted(glob.glob(os.path.join(RIPPED, 'stg*_t*.png'))):
        k = os.path.basename(p)[:-4]
        j['auto'][k] = guess(features(p))
    json.dump(j, open(CFG, 'w'), indent=1, sort_keys=True)
    from collections import Counter
    print('classified', len(j['auto']), dict(Counter(j['auto'].values())))


def final(j, k):
    return j['overrides'].get(k, j['auto'].get(k, 'painted'))


def show(stage, out):
    j = load()
    fs = sorted(glob.glob(os.path.join(RIPPED, stage + '_*_t*.png')))
    S, C = 96, 10
    R = (len(fs) + C - 1) // C
    im = Image.new('RGB', (C * S, R * (S + 12)), (20, 20, 20)); d = ImageDraw.Draw(im)
    for i, p in enumerate(fs):
        k = os.path.basename(p)[:-4]
        c = final(j, k)
        x, y = (i % C) * S, (i // C) * (S + 12)
        im.paste(Image.open(p).convert('RGB').resize((S - 2, S - 2)), (x, y + 12))
        d.rectangle([x, y, x + S - 2, y + 11], fill=SHOW[c])
        d.text((x + 2, y), k.replace(stage + '_', '').replace('world_', 'w').replace('prop', 'p') + ' ' + c[:5],
               fill=(0, 0, 0))
    im.save(out)
    print('sheet', stage, len(fs), '->', out)


if __name__ == '__main__':
    if sys.argv[1] == 'classify': classify()
    elif sys.argv[1] == 'show': show(sys.argv[2], sys.argv[3])
