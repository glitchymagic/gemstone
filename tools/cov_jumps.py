#!/usr/bin/env python3
"""fx-cov: one-frame position jumps (teleports) in a tape run, both sides, @place frames excluded.
  FID_OUT=dir cov_jumps.py TAPE...   frames where a fighter moved > 60 cm (xz) or > 60 cm (y) in one frame"""
import json, os, sys
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + '/'
sys.path.insert(0, REPO + 'tools')
import tapes
D = './dumps/fidelity/'
OUTD = os.environ.get('FID_OUT', D).rstrip('/') + '/'


def places(t):
    rows = tapes.parse(open(REPO + f'game/tests/tapes/{t}.tape').read())
    return {k for k, r in enumerate(rows) if any(c.startswith('place') for c in r[2])}


def jumps(rows, skip):
    out = []
    for k in range(1, len(rows)):
        if k - 1 in skip or k in skip: continue
        for i in range(2):
            a, b = rows[k - 1]['p'][i], rows[k]['p'][i]
            dxz = ((a['x'] - b['x']) ** 2 + (a['z'] - b['z']) ** 2) ** 0.5
            dy = abs(a['y'] - b['y'])
            if dxz > 60 or dy > 60:
                out.append((k, i + 1, round(dxz), round(b['y'] - a['y']), [b['x'], b['y'], b['z']], b['st']))
    return out


if __name__ == '__main__':
    for t in sys.argv[1:]:
        sk = places(t)
        for side, path in (('orig', D + f'o_{t}.jsonl'), ('rem', OUTD + f'r_{t}.jsonl')):
            if not os.path.exists(path): continue
            j = jumps([json.loads(l) for l in open(path)], sk)
            print(t, side, len(j), j[:6])
