#!/usr/bin/env python3
"""Contact sheet of captured motions: per motion, the game's own bone positions (character space, side view
z -> right, y -> up) at 4 moments (start blue, 1/3 green, 2/3 orange, end red), with id, length, loop flag.
Usage: sheet.py skel.json segs.json out.png cap1.bin ..."""
import json, os, sys
import numpy as np
from PIL import Image, ImageDraw
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mocap, clips

skel = json.load(open(sys.argv[1])); segs = sys.argv[2]; out = sys.argv[3]; caps = sys.argv[4:]
par = skel['parent']
CW, CH, COLS = 120, 150, 10
rows = (len(caps) + COLS - 1) // COLS
im = Image.new('RGB', (CW * COLS, CH * rows), (250, 250, 250)); dr = ImageDraw.Draw(im)
Mi = np.linalg.inv(clips.mchar())
cols = [(40, 80, 220), (30, 160, 60), (240, 140, 20), (220, 30, 30)]
for i, cp in enumerate(caps):
    d = mocap.decode(cp, segs); s, L, loop, _ = clips.segment(d)
    x0, y0 = (i % COLS) * CW, (i // COLS) * CH
    dr.rectangle([x0, y0, x0 + CW - 1, y0 + CH - 1], outline=(200, 200, 200))
    for ci, fr in enumerate([0, L // 3, 2 * L // 3, L - 1]):
        P = (d['W'][s + fr, :22, 3, :] @ Mi)[:, :3]
        def xy(p): return (x0 + CW / 2 + p[2] * 0.45, y0 + CH - 12 - p[1] * 0.55)
        for k in range(1, 22):
            if par[k] >= 0 and par[k] < 22:
                dr.line([xy(P[par[k]]), xy(P[k])], fill=cols[ci], width=2)
        dr.ellipse([xy(P[4])[0] - 3, xy(P[4])[1] - 3, xy(P[4])[0] + 3, xy(P[4])[1] + 3], outline=cols[ci])
    tag = os.path.splitext(os.path.basename(cp))[0].split('_', 1)[1]
    dr.text((x0 + 3, y0 + 2), f'{tag} {L}{"L" if loop else ""}', fill=(0, 0, 0))
im.save(out)
print(out, im.size)
