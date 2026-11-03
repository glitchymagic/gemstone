#!/usr/bin/env python3
"""The original in-fight HUD portraits + name banners: FACE00..FACE10.BIN (MODEL.BIN-style compression over
twiddled ARGB4444, stored upside-down; 128x128, FACE00 256x128). Writes game/assets/ripped/ui/faceNN.png (+ 4x
upscaled faceNN_4x.png via tools/upscale.py). NN = fighter index (00 Falcon ... 09 Valgas, 10 Final Valgas)."""
import os, subprocess, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pstex
from PIL import Image
R = './'
out = R + 'game/assets/ripped/ui/'; tmp = tempfile.mkdtemp(prefix='faces_') + '/'
os.makedirs(out, exist_ok=True); os.makedirs(tmp, exist_ok=True)
for i in range(11):
    d = pstex.decompress(open(R + f'rip/fs/FACE{i:02d}.BIN', 'rb').read())[0]
    w, h = (256, 128) if len(d) == 65536 else (128, 128)
    img = pstex.decode(d, w, h, 0x102).transpose(Image.FLIP_TOP_BOTTOM)
    img.save(tmp + f't{i:02d}.png')
    img.save(out + f'face{i:02d}.png')
    print(i, w, h)
subprocess.run([sys.executable, R + 'tools/upscale.py', tmp, tmp + 'up'], check=True, capture_output=True)
for i in range(11):
    os.replace(tmp + f'up/t{i:02d}.png', out + f'face{i:02d}_4x.png')
