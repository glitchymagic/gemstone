#!/usr/bin/env python3
"""Per-attempt move chains of a per-fighter tape: P1's motion sequence (kind/id x frames) and P2's damage between two
@place rows, original vs remaster.  [FID_OUT=dir] fidelity_moves.py TAPE (FID_OUT: where the r_*.jsonl are)"""
import json, os, sys
sys.path.insert(0, './tools')
import tapes
R = './'
LABELS = ['near X string', 'near Y string', 'far X string', 'far Y string', 'jump X / jump Y', 'grab (B)',
          'PC: drives, air drives, fusion P', 'PC: fusion K']


def chains(rows, a, b, i=0):
    out, prev, n = [], None, 0
    for r in rows[a:b]:
        p = r['p'][i]
        k = (p['kind'], p['mot']) if p['st'] not in (0, 31, 32, 2) else None
        if k != prev:
            if prev: out.append(f'{prev[0]}/{prev[1]}x{n}')
            prev, n = k, 0
        n += 1
    if prev: out.append(f'{prev[0]}/{prev[1]}x{n}')
    return out


def run(t):
    rows = tapes.parse(open(R + f'game/tests/tapes/{t}.tape').read())
    starts = [k for k, r in enumerate(rows) if any(c.startswith('place 1') for c in r[2])] + [len(rows)]
    o = [json.loads(l) for l in open(R + f'dumps/fidelity/o_{t}.jsonl')]
    m = [json.loads(l) for l in open(os.environ.get('FID_OUT', R + 'dumps/fidelity').rstrip('/') + f'/r_{t}.jsonl')]
    print(f'== {t}')
    res = []
    for j in range(len(starts) - 1):
        a, b = starts[j], starts[j + 1]
        co, cm = chains(o, a, b), chains(m, a, b)
        do = o[a]['p'][1]['hp'] - min(r['p'][1]['hp'] for r in o[a:b])
        dm = m[a]['p'][1]['hp'] - min(r['p'][1]['hp'] for r in m[a:b]) if b <= len(m) else None
        lab = LABELS[j] if j < len(LABELS) else str(j)
        ok = [x.split('x')[0] for x in co] == [x.split('x')[0] for x in cm]
        print(f'  {lab:32s} {"SAME-IDS" if ok else "DIFF"}\n     orig {" ".join(co)[:150]}  dmg {do}\n     rem  {" ".join(cm)[:150]}  dmg {dm}')
        res.append(ok)
    return res


if __name__ == '__main__':
    tot = []
    for t in sys.argv[1:]: tot += run(t)
    print(f'attempts with identical motion-id chains: {sum(tot)}/{len(tot)}')
