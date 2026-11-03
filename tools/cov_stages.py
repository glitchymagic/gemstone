#!/usr/bin/env python3
"""fx-cov: per-stage summary of the stage tapes (stg_NN, tools/cov_tapes.py) for docs/COVERAGE.md.
  FID_OUT=dir cov_stages.py [stg_00 ...]
Per stage: where the 16 runs into walls / edges ended (frame +89 of each run block, both fighters: how many within 1 /
10 cm of the original, median distance), frames in the wall kick (state 38 orig; the remaster's k2/206 rows), the
ledge hop (state 17), pole swings (state 34), one-frame moves > 60 cm while running / in the air (states 31 / 5 / 2 /
34: teleports; launches and throws excluded), the floor gem (the original's frame + spot from o_TAPE.obj.jsonl)."""
import json, os, statistics, sys
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + '/'
sys.path.insert(0, REPO + 'tools')
import cov_blocks, cov_jumps, fidelity_diff as FD
D = './dumps/fidelity/'
OUTD = os.environ.get('FID_OUT', D).rstrip('/') + '/'
MOVE = {31, 5, 2, 34, 0, 32}


def count(rows, pred):
    return sum(1 for r in rows for i in range(2) if pred(r['p'][i]))


def floor_gem(t):
    p = D + f'o_{t}.obj.jsonl'
    if not os.path.exists(p): return None
    for f, ln in enumerate(open(p)):
        for o in json.loads(ln):
            if o[1] == 3 and o[3] == 5 and o[9] == 0 and any(o[5:8]): return f, o[5:8]
    return None


def summary(t):
    o, r = FD.load(D + f'o_{t}.jsonl'), FD.load(OUTD + f'r_{t}.jsonl')
    old = cov_blocks.VERBOSE
    import io, contextlib
    with contextlib.redirect_stdout(io.StringIO()): cov_blocks.main(t)
    bl = json.load(open(OUTD + f'reports/{t}.blocks.json'))
    ds = [p['run_end']['d_cm'] for b in bl if b['what'].startswith('run ') for p in b['p']]
    sk = cov_jumps.places(t)
    tj = {side: [j for j in cov_jumps.jumps(rows, sk) if j[5] in MOVE] for side, rows in (('o', o), ('r', r))}
    res = {'tape': t, 'runs': len(ds), 'within1': sum(d <= 1 for d in ds), 'within10': sum(d <= 10 for d in ds),
           'median_cm': round(statistics.median(ds), 1) if ds else None,
           'wallkick_o': count(o, lambda p: p['st'] == 38), 'wallkick_r': count(r, lambda p: p['st'] == 38),
           'k206_r': count(r, lambda p: p['kind'] == 2 and p['mot'] == 206),
           'k206_o': count(o, lambda p: p['kind'] == 2 and p['mot'] == 206),
           'hop_o': count(o, lambda p: p['st'] == 17), 'hop_r': count(r, lambda p: p['st'] == 17),
           'pole_o': count(o, lambda p: p['st'] == 34), 'pole_r': count(r, lambda p: p['st'] == 34),
           'tele_o': tj['o'], 'tele_r': tj['r'], 'gem': floor_gem(t)}
    return res


if __name__ == '__main__':
    names = sys.argv[1:] or [f'stg_{n}' for n in ('00', '10', '20', '30', '40', '50', '60', '70', '80', '90', 'a0')]
    out = []
    print('| tape | run ends <=1 / <=10 cm of 16 | median cm | wall kick st38 o/r (k2/206 rows o/r) | ledge hop st17 o/r |'
          ' pole st34 o/r | one-frame >60 cm moves o/r (remaster: frame P state at x,y,z) | floor gem (orig frame, x,y,z) |')
    print('|---|---|---|---|---|---|---|---|')
    for t in names:
        if not os.path.exists(OUTD + f'r_{t}.jsonl') or not os.path.exists(D + f'o_{t}.jsonl'):
            print(f'| {t} | not run | | | | | | |'); continue
        s = summary(t); out.append(s)
        tr = '; '.join(f'f{j[0]} P{j[1]} st{j[5]} {j[2]}/{j[3]:+d} cm at ({j[4][0]:.0f},{j[4][1]:.0f},{j[4][2]:.0f})' for j in s['tele_r'][:3])
        print(f"| {t} | {s['within1']} / {s['within10']} | {s['median_cm']} | {s['wallkick_o']}/{s['wallkick_r']} "
              f"({s['k206_o']}/{s['k206_r']}) | {s['hop_o']}/{s['hop_r']} | {s['pole_o']}/{s['pole_r']} | "
              f"{len(s['tele_o'])}/{len(s['tele_r'])} {tr} | {s['gem'][0]}, {s['gem'][1]} |" if s['gem'] else '- |')
    json.dump(out, open(OUTD + 'reports/stages_summary.json', 'w'), indent=1)
