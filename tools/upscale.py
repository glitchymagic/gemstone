#!/usr/bin/env python3
"""4x upscale of ripped textures with Real-ESRGAN x4plus_anime_6B (spandrel, MPS).
Pads with wrap-around before upscaling so tiling textures stay seamless; alpha is upscaled
separately (bicubic) and re-attached. Usage: upscale.py <in_dir> <out_dir>"""
import glob, os, sys, types
try:
    import lzma  # noqa
except ImportError:  # this pyenv build lacks _lzma; spandrel only imports it
    _m = types.ModuleType("lzma"); _m.open = None; _m.LZMAFile = None; _m.LZMAError = Exception; sys.modules["lzma"] = _m
import numpy as np, torch
from PIL import Image
from spandrel import ModelLoader
src, dst = sys.argv[1], sys.argv[2]
os.makedirs(dst, exist_ok=True)
dev = 'mps' if torch.backends.mps.is_available() else 'cpu'
model = ModelLoader().load_from_file(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'bin/RealESRGAN_x4plus_anime_6B.pth')).to(dev).eval()
P = 8
for f in sorted(glob.glob(os.path.join(src, 't*.png'))):
    out = os.path.join(dst, os.path.basename(f))
    if os.path.exists(out): continue
    im = Image.open(f).convert('RGBA'); a = np.asarray(im)
    rgb = np.pad(a[..., :3], ((P, P), (P, P), (0, 0)), mode='wrap').astype(np.float32) / 255.0
    with torch.no_grad():
        t = torch.from_numpy(rgb).permute(2, 0, 1)[None].to(dev)
        y = model(t).clamp(0, 1)[0].permute(1, 2, 0).cpu().numpy()
    y = (y[4 * P:-4 * P, 4 * P:-4 * P] * 255 + 0.5).astype(np.uint8)
    al = Image.fromarray(a[..., 3]).resize((y.shape[1], y.shape[0]), Image.BICUBIC)
    o = Image.fromarray(y, 'RGB'); o.putalpha(al)
    o.save(out)
print('upscaled ->', dst, len(glob.glob(os.path.join(dst, '*.png'))))
