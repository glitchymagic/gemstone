#!/usr/bin/env python3
"""Segment view of a fidelity log: one line per (state, motion) run with its length, displacement and health change.
  fidelity_show.py LOG.jsonl [P=1|2] [FROM] [TO]"""
import json, math, sys


def segs(rows, i, a=0, b=None):
    out, cur = [], None
    for r in rows[a:b]:
        p = r['p'][i]
        k = (p['st'], p['kind'], p['mot'])
        if cur is None or k != cur['k']:
            if cur: out.append(cur)
            cur = dict(k=k, f0=r['f'], n=0, x0=(p['x'], p['y'], p['z']), hp0=p['hp'], fr0=p['fr'], ang=p['ang'])
        cur['n'] += 1; cur['x1'] = (p['x'], p['y'], p['z']); cur['hp1'] = p['hp']; cur['fr1'] = p['fr']
        cur['ymax'] = max(cur.get('ymax', -1e9), p['y'])
    if cur: out.append(cur)
    return out


def show(rows, i, a=0, b=None):
    for s in segs(rows, i, a, b):
        dx = s['x1'][0] - s['x0'][0]; dz = s['x1'][2] - s['x0'][2]
        print(f"{s['f0']:5d} +{s['n']:3d}  s{s['k'][0]:<3d} k{s['k'][1]}/{s['k'][2]:<4d} fr{s['fr0']}-{s['fr1']:<4d}"
              f" d={math.hypot(dx, dz):6.1f}cm dy={s['x1'][1] - s['x0'][1]:6.1f} ymax={s['ymax']:6.1f} hp {s['hp0']}->{s['hp1']} ang {s['ang']}")


if __name__ == '__main__':
    rows = [json.loads(l) for l in open(sys.argv[1])]
    i = int(sys.argv[2]) - 1 if len(sys.argv) > 2 else 0
    a = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    b = int(sys.argv[4]) if len(sys.argv) > 4 else None
    show(rows, i, a, b)
