#!/usr/bin/env python3
"""The original's fight camera on one stage, from its camera object read out of RAM every frame
(tools/ref_londo.py cam TAG: view matrix, eye +0x450, desired target +0x474, smoothed target +0x480, P1/P2 positions).
Writes into game/assets/ripped/STG_info.json:
  cam_zones  = which yaw preset the game uses where: a grid over the desired target's x/z (cell CELL cm), each cell the
               preset seen most there in steady frames (unseen cells: the nearest seen one)
  cam_levels = the stepped zoom: horizontal eye distance per fighter-separation band + eye height over the target
Measured on Londo 2026-10-23 (camL, 10,800 frames, both sides the game's AI): yaws -135 (55%) / -115 (31%) / -155 (2%),
yaw changes take ~33 frames; distance 594 / 797 / 1195 cm for separations < 3 / 3-7 / > 7 m; target = the fighters'
hip midpoint (RAM positions are hip height; median difference 2 cm); eye ~0.36 x distance above it, capped at 500 cm.
  cam_zones.py CAPTAG STG    e.g. cam_zones.py camL stg00"""
import json, sys
import numpy as np

R = './'
FS = 116
CELL = 200
PRESETS = [-135.0, -115.0, -155.0]


def load(tag):
    raw = open(R + f'dumps/cap/{tag}.bin', 'rb').read()
    n = len(raw) // FS
    a = np.frombuffer(raw[:n * FS], dtype=np.uint8).reshape(n, FS)
    f3 = lambda o: np.frombuffer(a[:, o:o + 12].tobytes(), '<f4').reshape(n, 3)
    return f3(48), f3(60), f3(72), f3(84), f3(96)


def main(tag, stg):
    E, T, S, P1, P2 = load(tag)
    d = E - S
    yaw = np.degrees(np.arctan2(d[:, 0], d[:, 2]))
    lab = np.full(len(yaw), -1)
    for i, p in enumerate(PRESETS): lab[np.abs(yaw - p) < 0.6] = i
    m = lab >= 0
    xs = np.floor(T[m, 0] / CELL).astype(int); zs = np.floor(T[m, 2] / CELL).astype(int); L = lab[m]
    x0, x1, z0, z1 = xs.min(), xs.max(), zs.min(), zs.max()
    cols, rows = x1 - x0 + 1, z1 - z0 + 1
    cnt = np.zeros((rows, cols, len(PRESETS)))
    for x, z, l in zip(xs, zs, L): cnt[z - z0, x - x0, l] += 1
    seen = cnt.sum(2) > 0
    grid = np.argmax(cnt, 2)
    sy, sx = np.nonzero(seen)
    for r in range(rows):
        for c in range(cols):
            if not seen[r, c]:
                k = np.argmin((sy - r) ** 2 + (sx - c) ** 2)
                grid[r, c] = grid[sy[k], sx[k]]
    hd = np.hypot(d[:, 0], d[:, 2])
    sep = np.hypot(*(P1 - P2)[:, [0, 2]].T)
    steady = m & (np.linalg.norm(T - S, axis=1) < 15) & (np.abs((P1 - P2)[:, 1]) < 60)
    bands = [(0, 300), (300, 700), (700, 1200)]
    dist = [float(np.median(hd[steady & (sep >= lo) & (sep < hi)])) for lo, hi in bands]
    info_p = R + f'game/assets/ripped/{stg}_info.json'
    info = json.load(open(info_p))
    info['cam_zones'] = {'x0_cm': int(x0 * CELL), 'z0_cm': int(z0 * CELL), 'cell_cm': CELL, 'cols': int(cols),
                         'rows': int(rows), 'yaws_deg': PRESETS, 'grid': [[int(v) for v in row] for row in grid],
                         'blend_frames': 33, 'source': f'dumps/cap/{tag}.bin (tools/ref_londo.py cam), tools/cam_zones.py'}
    info['cam_levels'] = {'sep_cm': [300, 700], 'dist_cm': [round(v) for v in dist], 'eye_k': 0.36, 'eye_cap_cm': 500,
                          'target': 'hip midpoint'}
    json.dump(info, open(info_p, 'w'), indent=1)
    print(stg, 'zones', cols, 'x', rows, 'levels', [round(v) for v in dist])
    for row in reversed(grid.tolist()): print(' ', ''.join('ABC'[v] for v in row))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
