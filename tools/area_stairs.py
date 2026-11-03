#!/usr/bin/env python3
"""Stair faces into the area (BUG-107 part 2).

The area raster (tools/stage_area.py) only holds spots where the probe could put a fighter, and a fighter can't be put
on a step's face: every face of a staircase is a floorless band 30-50 cm deep that the 2D area leaves OUT, so the
upper treads come out with sdf <= 10 cm and the clamp pushes runners back down (Londo's back stairs 0 > 30 > ... > 240 cm:
CPU runners after the disc's gem spots ran in place, w7). The disc walks these stairs.

This post-pass fills an outside sdf cell when, along x or z, an inside cell with a floor lies on BOTH sides within
GAP_CM in total and the two floors differ by more than LEDGE_MIN and at most the stage's step_up (a face you step up,
not a wall or a drop), then writes sdf + the change that makes as sdf_stairs (distance transforms as in stage_area.py), read for runners only. The floor raster is left alone
(core_ground's step rule moves the feet across the face).

Usage: tools/area_stairs.py STAGE [--write]   (dry run: prints the cells it would fill)
"""
import base64, json, sys
import numpy as np
from scipy.ndimage import distance_transform_edt

GAP_CM = 60.0       # the widest face band filled (Londo's: 40-50 cm)
LEDGE_MIN_CM = 15.0  # arena.gd LEDGE_MIN
P = 'game/assets/fidelity/%s_area.json'


def dec(s, h, w):
    return np.frombuffer(base64.b64decode(s), '<i2').reshape(h, w).astype(np.float64)


def sdf_of(mask, cell):
    s = distance_transform_edt(mask) * cell - distance_transform_edt(~mask) * cell
    return np.where(mask, s - cell / 2, s + cell / 2)


def main():
    st = sys.argv[1]; write = '--write' in sys.argv
    d = json.load(open(P % st))
    g = d['sdf']; x0, z0, c, W, H = g['x0'], g['z0'], g['cell'], g['w'], g['h']
    sdf = dec(g['i16'], H, W)
    air = dec(d['sdf_air'], H, W) if isinstance(d.get('sdf_air'), str) else sdf.copy()
    f = d['floor']; fx0, fz0, fc, FW, FH, n = f['x0'], f['z0'], f['cell'], f['w'], f['h'], f['n']
    flo = np.frombuffer(base64.b64decode(f['i16']), '<i2').reshape(FH, FW, n)
    step_up = float(d.get('step_up_cm', 65))

    def levels(x, z):
        i, j = int(round((z - fz0) / fc)), int(round((x - fx0) / fc))
        if not (0 <= i < FH and 0 <= j < FW): return []
        return [int(v) for v in flo[i, j] if v != -32768]

    mask = sdf > 0
    fill = np.zeros_like(mask)
    k_max = int(GAP_CM // c)
    for i in range(H):
        for j in range(W):
            if mask[i, j]: continue
            x, z = x0 + j * c, z0 + i * c
            for di, dj in ((0, 1), (1, 0)):
                a = b = None
                for k in range(1, k_max + 1):   # nearest inside cell each way
                    ii, jj = i - di * k, j - dj * k
                    if 0 <= ii < H and 0 <= jj < W and mask[ii, jj]: a = k; break
                for k in range(1, k_max + 1):
                    ii, jj = i + di * k, j + dj * k
                    if 0 <= ii < H and 0 <= jj < W and mask[ii, jj]: b = k; break
                if a is None or b is None or (a + b - 1) * c > GAP_CM: continue
                la = levels(x - dj * a * c, z - di * a * c); lb = levels(x + dj * b * c, z + di * b * c)
                if any(LEDGE_MIN_CM < abs(p - q) <= step_up + 0.5 for p in la for q in lb) and \
                        not any(abs(p - q) <= LEDGE_MIN_CM for p in la for q in lb):
                    fill[i, j] = True; break
    print('%s: %d cells to fill (%.2f m2), area %.1f m2' % (st, fill.sum(), fill.sum() * c * c / 1e4, mask.sum() * c * c / 1e4))
    if not write: return
    # only the change the fill makes: the stored sdf has more in it than a plain distance transform (patches, the
    # probe's own edges: recomputing it from the mask moves cells all over the stage by up to 2 m)
    sdf2 = sdf + (sdf_of(mask | fill, c) - sdf_of(mask, c))
    # a grid of its own, for runners / walkers only (arena.gd run_sdf): a body thrown / knocked into a face band is
    # still pushed out of it as before (filling the area itself left a thrown Wang-Tang lying 73 frames in a stg40 band)
    d['sdf_stairs'] = base64.b64encode(np.round(sdf2).astype('<i2').tobytes()).decode()
    am = air > 0   # and the air area's (the out-of-map check of a jump off the stairs)
    a2 = air + (sdf_of(am | fill, c) - sdf_of(am, c))
    d['sdf_air_stairs'] = base64.b64encode(np.round(a2).astype('<i2').tobytes()).decode()
    d['stairs_note'] = 'tools/area_stairs.py (BUG-107): sdf_stairs = sdf + %d stair-face cells (runners only)' % int(fill.sum())
    json.dump(d, open(P % st, 'w'), separators=(',', ':'))
    print('written')


if __name__ == '__main__':
    main()
