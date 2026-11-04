#!/usr/bin/env python3
"""Remaster textures from the disc: decode the original PowerVR textures of a model (rip/fs/X.MDL + X_MODEL.BIN) and
upscale them with a chosen network, wrap-padded so tiling textures stay seamless (alpha upscaled bicubic, re-attached).
Usage:
  hd_tex.py decode X out_dir                      originals (t00.png ...) of X (P00, STG20, ...)
  hd_tex.py up MODEL.pth in_dir out_dir [t03 t35]  upscale (all t*.png, or just the listed ones), 4x
  hd_tex.py fighter P00 out_dir                    the Remaster set of a fighter form: tNN.png albedo (4x, the
      upscaler picked per texture: anime_6B where the texture is mostly skin, 4x-AnimeSharp elsewhere: it keeps logos
      and patterns closest to the disc's design), tNN_m.png class weights (R skin G hair B metal A leather) and
      tNN_s.png (R gem G eyes B inner ink line A painted shade), tNN_n.png (tangent-space normal map: the painted folds,
      seams and fine detail of the texture as height, per-class strength), all derived from the disc texture
The rip is read from $PS_RIP (default: rip/ of this checkout, read only)."""
import glob, os, sys, types
try:
    import lzma  # noqa
except ImportError:  # this pyenv build lacks _lzma; spandrel/torchvision only import it
    _m = types.ModuleType("lzma"); _m.open = None; _m.LZMAFile = None; _m.LZMAError = Exception; sys.modules["lzma"] = _m
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
RIP = os.environ.get('PS_RIP', './rip')
MODELS = os.environ.get('PS_UPSCALERS', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'bin'))


def originals(name):
    import psmdl, pstex
    name = name.upper()
    parts, tex, _ = psmdl.parse(open(f'{RIP}/fs/{name}.MDL', 'rb').read())
    blob, _, _ = pstex.decompress(open(f'{RIP}/fs/{name}_MODEL.BIN', 'rb').read())
    base = tex[0][3]
    out = []
    for w, h, fmt, addr in tex:
        o = addr - base
        out.append(pstex.decode(blob[o:o + pstex.tex_size(w, h, fmt)], w, h, fmt))
    return out


_net = {}


def net(path):
    if path not in _net:
        import torch
        from spandrel import ModelLoader
        dev = 'mps' if torch.backends.mps.is_available() else 'cpu'
        _net[path] = (ModelLoader().load_from_file(path).to(dev).eval(), dev)
    return _net[path]


def upscale(im, model_path, pad=8):
    import torch
    m, dev = net(model_path)
    a = np.asarray(im.convert('RGBA'))
    rgb = np.pad(a[..., :3], ((pad, pad), (pad, pad), (0, 0)), mode='wrap').astype(np.float32) / 255.0
    with torch.no_grad():
        t = torch.from_numpy(rgb).permute(2, 0, 1)[None].to(dev)
        y = m(t).clamp(0, 1)[0].permute(1, 2, 0).cpu().numpy()
    s = y.shape[0] // rgb.shape[0]
    y = (y[s * pad:-s * pad, s * pad:-s * pad] * 255 + 0.5).astype(np.uint8)
    al = Image.fromarray(a[..., 3]).resize((y.shape[1], y.shape[0]), Image.BICUBIC)
    o = Image.fromarray(y, 'RGB'); o.putalpha(al)
    return o


UP_SKIN = 'RealESRGAN_x4plus_anime_6B.pth'
UP_REST = '4x-AnimeSharp.pth'


def derived(up, w):
    """Upscaled RGBA + class weights at that size -> (mask_m, mask_s) RGBA uint8 images."""
    from scipy.ndimage import gaussian_filter
    blur = lambda x, r: gaussian_filter(x, r, mode='wrap')
    a = np.asarray(up.convert('RGBA')).astype(np.float32) / 255.0
    lum = a[..., :3] @ np.array([0.299, 0.587, 0.114], np.float32)
    s = max(a.shape[0] / 256.0, 0.25)
    # inner ink lines: thin strokes darker than their surroundings (the disc's own painted lines and seams)
    # + borders between material classes
    loc = blur(lum, 2.2 * s)
    stroke = np.clip((loc - lum) * 6.0 - 0.12, 0, 1)
    cls = w.argmax(-1).astype(np.float32)
    edge = (cls != np.roll(cls, 1, 0)) | (cls != np.roll(cls, 1, 1))
    edge = np.clip(blur(edge.astype(np.float32), 0.7 * s) * 2.0, 0, 1) * 0.6
    line = np.clip(np.maximum(stroke, edge), 0, 1)
    # painted shade: the disc artists' folds and shadows, relative to the local colour (0.5 = flat)
    big = blur(lum, 9.0 * s)
    shade = np.clip(0.5 + (lum / np.maximum(big, 0.03) - 1.0) * 0.9, 0, 1)
    m = np.stack([w[..., 1], w[..., 2], w[..., 3], w[..., 4]], -1)
    sm = np.stack([w[..., 5], w[..., 6], line, shade], -1)
    # alpha is stored as 0.1 + 0.9 * value: Godot's importer (fix_alpha_border) repaints the RGB of texels whose alpha
    # is under 20/255, which would wipe the other three channels; the shader decodes it
    x4 = lambda x: np.concatenate([x[..., :3], 0.1 + 0.9 * x[..., 3:]], -1)
    q = lambda x: Image.fromarray((np.clip(x4(x), 0, 1) * 255 + 0.5).astype(np.uint8), 'RGBA')
    return q(m), q(sm)


# normal-map strength per class (CLASSES order: cloth skin hair metal leather gem eyes): skin stays smooth (the SSS
# softens it further), cloth/leather folds and seams read as relief, eyes stay flat
NSTR = np.array([1.0, 0.3, 0.8, 0.6, 1.0, 0.35, 0.0], np.float32)


def normal_map(up, w, sm):
    """Upscaled RGBA, class weights (H, W, 7), the _s map (RGBA uint8 image) -> tangent-space normal map (RGB, OpenGL
    convention, as Godot expects). Height = the texture's painted shade (folds) + its ink strokes as grooves + a little
    fine high-pass detail; all of it read from the disc texture itself."""
    from scipy.ndimage import gaussian_filter
    blur = lambda x, r: gaussian_filter(x, r, mode='wrap')
    a = np.asarray(up.convert('RGBA')).astype(np.float32) / 255.0
    s4 = np.asarray(sm).astype(np.float32) / 255.0
    lum = a[..., :3] @ np.array([0.299, 0.587, 0.114], np.float32)
    s = max(a.shape[0] / 256.0, 0.25)
    line = s4[..., 2]
    shade = (s4[..., 3] - 0.1) / 0.9
    fine = lum - blur(lum, 1.2 * s)
    h = (shade - 0.5) * 2.2 * s - blur(line, 0.8 * s) * 1.6 * s + fine * 1.5 * s
    k = (w @ NSTR).astype(np.float32) * (a[..., 3] > 0.5)
    h = blur(h, 0.6 * s)
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    n = np.stack([-dx * k, dy * k, np.ones_like(h)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return Image.fromarray((n * 127.5 + 127.5 + 0.5).clip(0, 255).astype(np.uint8), 'RGB')


def fighter(name, out):
    import hd_classes
    fid = name.lower()
    cfg = hd_classes.config(fid)
    heads = hd_classes.head_textures(fid)
    os.makedirs(out, exist_ok=True)
    for i, im in enumerate(originals(name)):
        k = 't%02d' % i
        stale = os.path.exists(f'{out}/{k}_m.png') and os.path.getmtime(f'{out}/{k}_m.png') < os.path.getmtime(hd_classes.CFG)
        if not stale and all(os.path.exists(f'{out}/{k}{x}.png') for x in ('', '_m', '_s', '_n')): continue
        if os.path.exists(f'{out}/{k}.png') and stale:   # classes re-authored: masks + normal map again, same albedo
            up = Image.open(f'{out}/{k}.png')
            w = hd_classes.weights(up, cfg, k, k in heads)
            m, sm = derived(up, w)
            m.save(f'{out}/{k}_m.png'); sm.save(f'{out}/{k}_s.png')
        elif all(os.path.exists(f'{out}/{k}{x}.png') for x in ('', '_m', '_s')):   # older set: add the normal map
            up = Image.open(f'{out}/{k}.png'); sm = Image.open(f'{out}/{k}_s.png')
            w = hd_classes.weights(up, cfg, k, k in heads)
        else:
            w0 = hd_classes.weights(im, cfg, k, k in heads)
            skin = w0[..., 1][np.asarray(im.convert('RGBA'))[..., 3] > 127].mean() if w0.size else 0
            up = upscale(im, os.path.join(MODELS, UP_SKIN if skin > 0.4 else UP_REST))
            w = hd_classes.weights(up, cfg, k, k in heads)
            m, sm = derived(up, w)
            up.save(f'{out}/{k}.png'); m.save(f'{out}/{k}_m.png'); sm.save(f'{out}/{k}_s.png')
        normal_map(up, w, sm).save(f'{out}/{k}_n.png')
    print('fighter textures', name, '->', out)


def main():
    cmd = sys.argv[1]
    if cmd == 'fighter':
        fighter(sys.argv[2], sys.argv[3]); return
    if cmd == 'decode':
        name, out = sys.argv[2], sys.argv[3]
        os.makedirs(out, exist_ok=True)
        for i, im in enumerate(originals(name)):
            im.save(f'{out}/t{i:02d}.png')
        print('decoded', name, '->', out)
    elif cmd == 'up':
        mp, src, dst = sys.argv[2], sys.argv[3], sys.argv[4]
        if not os.path.exists(mp): mp = os.path.join(MODELS, mp)
        only = set(sys.argv[5:])
        os.makedirs(dst, exist_ok=True)
        for f in sorted(glob.glob(os.path.join(src, 't*.png'))):
            k = os.path.basename(f)[:-4]
            if only and k not in only: continue
            out = os.path.join(dst, k + '.png')
            if os.path.exists(out): continue
            upscale(Image.open(f), mp).save(out)
        print('upscaled', src, '->', dst)


if __name__ == '__main__':
    main()
