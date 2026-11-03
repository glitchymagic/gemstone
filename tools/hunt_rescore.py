#!/usr/bin/env python3
"""fx-cov: re-score a breakage-hunt run (tools/hunt.sh) for the fidelity core. hunt.gd's `wedged` test asks
CharacterBody3D.is_on_floor(), which the core never sets (it moves fighters on Arena.core_ground, not move_and_slide), so
since the core landed every fighter standing still on the floor counts as "hanging in the air". This splits each wedged
occurrence by the core's own state id (ctx gst of the fighter): airborne core states = a real wedge, the rest = a false
positive of the test. Other classes are counted as they are.
  hunt_rescore.py RUN_DIR [OLD_RUN_DIR]"""
import collections, glob, json, os, sys

AIR = {5, 14, 27, 34, 38}   # core gst ids a fighter can hang in: air, falling off a step, reaction flight, pole, wall kick


def score(d):
    occ, distinct = collections.Counter(), collections.defaultdict(set)
    real = []
    for p in glob.glob(os.path.join(d, '*.jsonl')):
        for ln in open(p):
            try: x = json.loads(ln)
            except ValueError: continue
            c = x.get('cls')
            if not c: continue
            if c == 'wedged':
                ctx = x.get('ctx', {}); who = x.get('who', 0)
                ps = ctx.get('p', [])
                g = ps[who].get('gst') if who < len(ps) else None
                if g is not None and g not in AIR:
                    c = 'wedged_fp'
                else:
                    real.append((os.path.basename(p)[:-6], x.get('key'), g, ctx.get('f')))
            occ[c] += 1; distinct[c].add(x.get('key'))
    return occ, {k: len(v) for k, v in distinct.items()}, real


if __name__ == '__main__':
    o, dn, real = score(sys.argv[1])
    old = score(sys.argv[2]) if len(sys.argv) > 2 else None
    print(f'{"class":14s} {"occurrences":>11s} {"distinct":>8s}' + ('   old occ / distinct' if old else ''))
    for c in sorted(set(o) | set(old[0] if old else {})):
        print(f'{c:14s} {o[c]:11d} {dn.get(c, 0):8d}' + (f'   {old[0][c]:8d} / {old[1].get(c, 0)}' if old else ''))
    print(f'real wedges (gst in {sorted(AIR)}): {len(real)}')
    for r in sorted(real)[:15]: print('  ', r)
