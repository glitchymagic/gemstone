#!/usr/bin/env python3
"""Summary of tools/arcade_ladder.sh runs: per run cleared / fights / continues / KO-TIME-draw rounds / issues, plus every
Godot ERROR / WARNING line (each one counts as a bug).  arcade_ladder.py OUTDIR"""
import glob, json, os, sys
d = sys.argv[1]
tot = dict(runs=0, cleared=0, issues=0, errors=0, time_rounds=0, draw_rounds=0, ko_rounds=0)
for f in sorted(glob.glob(d + '/*.log')):
    txt = open(f, errors='replace').read().splitlines()
    lad = [l for l in txt if l.startswith('LADDER ')]
    errs = [l for l in txt if l.startswith(('ERROR', 'WARNING', 'SCRIPT ERROR'))]
    tot['runs'] += 1; tot['errors'] += len(errs)
    if not lad:
        print(f'{os.path.basename(f)}: NO RESULT (crash / timeout) last: {txt[-1][:120] if txt else ""}')
        tot['issues'] += 1
        continue
    r = json.loads(lad[-1][7:])
    tot['cleared'] += int(bool(r['cleared'])); tot['issues'] += len(r['issues'])
    for k in ('time_rounds', 'draw_rounds', 'ko_rounds'): tot[k] += r[k]
    print(f"{os.path.basename(f)}: cleared {r['cleared']} fights {r['fights']} continues {r['continues']} rounds KO {r['ko_rounds']} "
          f"TIME {r['time_rounds']} draw {r['draw_rounds']} frames {r['frames']} issues {r['issues'][:3]} errors {len(errs)} {sorted(set(errs))[:2]}")
print('TOTAL', json.dumps(tot))
