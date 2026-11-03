#!/usr/bin/env python3
"""BUG-98: the air throw rule, decoded (docs/BRK.md "Air throws"), scored on every logged air punch.
Rule (per-character move code, e.g. Ryoma 0x0C069B70, the air punch's motion handler, every frame): if the attack's
hit flag +0x108 is set, 0x0C09C894(p) == 1 (the opponent is in this attack's hit list +0x11C (count +0x144) and the
flag is 1 = a landed hit, not a guard), the opponent is not Final Valgas (+4 != 10) and (the opponent is in Power Change
(+0x71F1) or his reaction machine has just started (+9 == 1)) -> +0x108 = 0, 0x0C0A2712(p, k4 motion): the thrower
state 28 (+9 = 2), the victim state 29 (+9 = 3). So an air punch becomes a throw exactly when its attack spheres land a
hit (the remaster's sphere test: Fighter._game_hit_update) - no distance rule; the logged throw frame is the hit frame.
  airgrab_check.py [-v]   every air punch (state 10 entered with k1/10) in dumps/fidelity/o_*.jsonl + cpu/*.jsonl:
                          outcome (throw = the thrower's next state 28 kind 4 / landed = the victim's health drops or
                          he enters state 27 within the punch / miss) and whether the decoded rule holds"""
import glob, json, os, sys
R = './'
D = R + 'dumps/fidelity/'
IDS = ['falcon', 'ryoma', 'wangtang', 'jack', 'gunrock', 'galuda', 'ayame', 'rouge', 'kraken', 'valgas', 'finalvalgas']
# fighters whose air punch handler has the grab call (literal 0x0C0A2712 in their move code 0x0C339070[char]):
# Ryoma 0x0C069BE6, Wang-Tang 0x0C06EC0C, Galuda 0x0C07AF22.., Ayame 0x0C07F994, Rouge 0x0C0829F2 (PC k1/107),
# Kraken 0x0C085B0E; Falcon / Jack / Gunrock / Valgas reach it through shared code (logged throws: k4/2, k4/3)


def ids_of(path):
    meta = path[:-6] + '.meta.json'
    name = os.path.basename(path)[:-6]
    tp = R + 'game/tests/tapes/' + name[2:] + '.tape'
    if os.path.exists(tp):
        kv = dict(x.split('=') for x in open(tp).readline()[2:].split() if '=' in x)
        return kv.get('p1'), kv.get('p2')
    if name.startswith('cpu_'):
        parts = name.split('_')
        return parts[1], parts[2]
    return None, None


def main(verbose):
    files = sorted(glob.glob(D + 'o_*.jsonl')) + sorted(glob.glob(D + 'cpu/cpu_*.jsonl'))
    files = [f for f in files if not f.endswith('.obj.jsonl')]
    tot = {}
    for fn in files:
        try:
            P = [json.loads(l) for l in open(fn)]
        except Exception:
            continue
        ids = ids_of(fn)
        for a in (0, 1):
            v = 1 - a
            for f in range(1, len(P) - 40):
                p, q = P[f]['p'][a], P[f - 1]['p'][a]
                if not (p['st'] == 10 and p['kind'] == 1 and p['mot'] == 10 and not (q['st'] == 10 and q['kind'] == 1 and q['mot'] == 10)):
                    continue
                vic_air = P[f]['p'][v]['y'] > P[f - 1]['p'][v]['y'] - 50 and P[f]['p'][v]['st'] in (4, 5, 14, 17, 31, 38, 24) or P[f]['p'][v]['st'] == 5
                out, fr = 'miss', None
                for k in range(f, min(len(P), f + 40)):
                    pa, pv = P[k]['p'][a], P[k]['p'][v]
                    if pa['st'] == 28 and pa['kind'] == 4: out, fr = 'throw', k - f; break
                    if pv['hp'] < P[k - 1]['p'][v]['hp'] or (pv['st'] == 27 and P[k - 1]['p'][v]['st'] != 27):
                        out, fr = 'landed', k - f; break
                    if not (pa['st'] == 10 and pa['kind'] == 1 and pa['mot'] == 10): break
                c = ids[a] or '?'
                vid = ids[v] or '?'
                key = (c, out)
                tot[key] = tot.get(key, 0) + 1
                if verbose or (out == 'landed' and vid != 'finalvalgas'):
                    print(os.path.basename(fn), f, c, '->', vid, out, 'row', fr, 'victim st', P[f]['p'][v]['st'],
                          'dy', round(P[f]['p'][v]['y'] - p['y']), 'pc', P[f]['p'][v]['pc'])
    print('per fighter (throw / landed without a throw / miss):')
    for c in sorted({k[0] for k in tot}):
        print(' ', c, tot.get((c, 'throw'), 0), tot.get((c, 'landed'), 0), tot.get((c, 'miss'), 0))


if __name__ == '__main__':
    main('-v' in sys.argv)
