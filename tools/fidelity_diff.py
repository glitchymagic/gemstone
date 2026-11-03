#!/usr/bin/env python3
"""Same-input diff: the original's per-frame log (tools/reflog.py, Flycast) vs the remaster's (game/tests/tape_run.gd) for
the same input tape. Frame 0 = the tape's first frame on both sides.
Reports, per player and field, the FIRST divergence and the share of frames that match, plus both sides' state / motion
timelines side by side around the first divergence.
Tolerances (docs/FIDELITY.md "Tolerances"): motion kind/id, motion frame, state, health, gems, Power Change exact;
position 1.0 cm (the original keeps x/y/z as f32 cm and moves in steps of 1.5-36 cm/frame, so a correct port is within
float rounding; 1 cm is far below anything a player can see and far above f32 noise at stage scale);
velocity 0.05 cm/frame; facing 64/65536 of a turn (0.35 deg).
  fidelity_diff.py ORIG.jsonl REM.jsonl [--json OUT] [--quiet]"""
import json, sys

TOL = {'x': 1.0, 'y': 1.0, 'z': 1.0, 'vx': 0.05, 'vy': 0.05, 'vz': 0.05, 'ang': 64}
EXACT = ['st', 'kind', 'mot', 'fr', 'hp', 'gems', 'pc']
FIELDS = EXACT + ['x', 'y', 'z', 'ang']


def load(p):
    return [json.loads(l) for l in open(p) if l.strip()]


def same(f, a, b):
    if a is None or b is None: return False
    if f == 'ang':
        d = abs(int(a) - int(b)) % 65536
        return min(d, 65536 - d) <= TOL['ang']
    if f in TOL: return abs(float(a) - float(b)) <= TOL[f]
    return a == b


def timeline(rows, i, a, b):
    out, prev = [], None
    for r in rows[max(0, a):b]:
        p = r['p'][i]
        k = (p['st'], p['kind'], p['mot'])
        if k != prev:
            out.append(f"{r['f']}:s{p['st']} k{p['kind']}/{p['mot']}")
            prev = k
    return out


def diff(orig, rem):
    n = min(len(orig), len(rem))
    res = {'frames': n, 'players': []}
    for i in range(2):
        pr = {}
        for f in FIELDS:
            first, ok = None, 0
            for k in range(n):
                a, b = orig[k]['p'][i].get(f), rem[k]['p'][i].get(f)
                if same(f, a, b): ok += 1
                elif first is None: first = (k, a, b)
            pr[f] = {'match': round(ok / max(1, n), 3), 'first': first}
        res['players'].append(pr)
    return res


def report(orig, rem, res):
    lines = [f"frames compared: {res['frames']}"]
    for i, pr in enumerate(res['players']):
        lines.append(f'--- P{i + 1}')
        for f, v in pr.items():
            fd = v['first']
            lines.append(f"  {f:5s} match {v['match'] * 100:5.1f}%  first diff: " +
                         (f"frame {fd[0]} orig {fd[1]} rem {fd[2]}" if fd else 'none'))
        fd = pr['st']['first'] or pr['mot']['first'] or pr['x']['first']
        if fd:
            k = fd[0]
            lines.append(f'  orig timeline from {max(0, k - 20)}: ' + ' '.join(timeline(orig, i, k - 20, k + 120)[:14]))
            lines.append(f'  rem  timeline from {max(0, k - 20)}: ' + ' '.join(timeline(rem, i, k - 20, k + 120)[:14]))
    return '\n'.join(lines)


if __name__ == '__main__':
    o, r = load(sys.argv[1]), load(sys.argv[2])
    res = diff(o, r)
    if '--json' in sys.argv: json.dump(res, open(sys.argv[sys.argv.index('--json') + 1], 'w'), indent=1)
    if '--quiet' not in sys.argv: print(report(o, r, res))
