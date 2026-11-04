#!/usr/bin/env python3
"""Stage object placement from the disc (no emulator): importer/stage_spec.json says WHICH parts a stage places and
WHERE in 1ST_READ.BIN their poses are; the numbers themselves are read from the player's 1ST_READ.BIN.
  stage_layout_disc.py STG00 out_layout.json
Sources (addresses in the 0x0C010000 mapping):
  desc       the stage descriptor (0x0C350B60 + stage*0x34, 13 words: [0..5] MDL part offset / size lists,
             [6] -> f32[3] rest position and [7] -> s32[3] rest rotation of every prop part from 10 up, [8] prop count,
             [9] breakage-piece count, [10] MDL bytes before the texture table, [11] texture-table bytes, [12] textures)
  tables     instance lists the stage's object code reads: n x f32[3] positions + a yaw list (s32, 65536 = 360 deg)
             or an s32[3] rotation list
  children   a part placed relative to every instance of another part (its descriptor pose is the local offset)
Output records match tools/stage_layout.py (part, 4x4 row-vector world matrix M, pole)."""
import json, os, struct, sys
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from mdt_decode import euler_rowmat
B = 0x0C010000
DESC = 0x0C350B60
STAGES = ['STG00', 'STG10', 'STG20', 'STG30', 'STG40', 'STG50', 'STG60', 'STG70', 'STG80', 'STG90', 'STGA0']


def mat(rot, t):
    m = np.eye(4); m[:3, :3] = euler_rowmat(np.asarray(rot, np.float64)); m[3, :3] = t
    return m


def layout(exe, stg, spec):
    w = lambda a, n, f='I': struct.unpack_from('<%d%s' % (n, f), exe, a - B)
    si = STAGES.index(stg.upper())
    d = w(DESC + si * 0x34, 13); n = d[8]
    pos = np.array(w(d[6], 3 * n, 'f')).reshape(n, 3); rot = np.array(w(d[7], 3 * n, 'i')).reshape(n, 3)
    desc = {10 + k: mat(rot[k], pos[k]) for k in range(n)}
    sp = spec[stg.lower()]
    out = []
    for p in sp['desc'] + sp.get('desc_rest', []):
        out.append((p, desc[p]))
    for t in sp['tables']:
        for k in range(t['n']):
            tp = [0.0, 0.0, 0.0] if t['pos'] == 'origin' else w(int(t['pos'], 16) + 12 * k, 3, 'f')
            r = t['rot']
            if r == 'zero': rr = [0, 0, 0]
            elif r == 'desc': rr = rot[t['part'] - 10]
            elif r.startswith('yaw@'): rr = [0, w(int(r[4:], 16) + 4 * k, 1, 'i')[0], 0]
            else: rr = list(w(int(r[4:], 16) + 12 * k, 3, 'i'))
            out.append((t['part'], mat(rr, tp)))
    for c in sp['children']:
        for p, m in list(out):
            if p == c['parent']:
                out += [(c['part'], desc[c['part']] @ m)] * c.get('n', 1)
    poles = set(sp.get('poles', []))
    return [{'part': int(p), 'M': np.round(m, 4).tolist(), 'pole': True} if p in poles else
            {'part': int(p), 'M': np.round(m, 4).tolist()} for p, m in out]


def main():
    stg, outp = sys.argv[1], sys.argv[2]
    exe = open(os.path.join(ROOT, 'rip', 'fs', '1ST_READ.BIN'), 'rb').read()
    spec = json.load(open(os.path.join(ROOT, 'importer', 'stage_spec.json')))
    lay = layout(exe, stg, spec)
    json.dump(lay, open(outp, 'w'), indent=1)
    print(len(lay), 'placed objects')


if __name__ == '__main__':
    main()
