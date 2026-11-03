#!/usr/bin/env python3
"""fx-flow: compare the round flow of the original (tools/flowlog.py log) with the remaster's (game/tests/flow_run.gd,
Fight.flow_row): the phase sequence with lengths (round phase byte 1 intro, 2 ready, 3 fight, 4 KO/TIME call, 5 poses),
MV_OK changes inside each phase, and per phase (except 3, where the fighting itself differs) each player's (state,
kind/motion) runs with their lengths.
  flow_diff.py ORIG.jsonl[:A-B] REM.jsonl[:A-B] [OUT.md]
Exact = same phase lengths and the same motion runs (state, kind, id, frames) in phases 1, 2, 4, 5."""
import json, sys


def load(spec):
    path, _, rng = spec.partition(':')
    rows = [json.loads(l) for l in open(path) if l.strip()]
    if rng:
        a, b = (int(x) if x else None for x in rng.split('-'))
        rows = rows[a:b]
    return rows


def runs(seq):
    out = []
    for v in seq:
        if out and out[-1][0] == v: out[-1][1] += 1
        else: out.append([v, 1])
    return out


def phases(rows):
    """[(phase, length, rows)] for every run of the phase byte"""
    out = []
    for r in rows:
        if out and out[-1][0] == r['phase']: out[-1][2].append(r)
        else: out.append([r['phase'], 0, [r]])
    for o in out: o[1] = len(o[2])
    return out


def fmt_runs(rs):
    return ' > '.join(f'{v}x{n}' for v, n in rs)


def motion_runs(rows, i):
    return runs([f"st{r['p'][i]['st']} k{r['p'][i]['kind']}/{r['p'][i]['mot']}" for r in rows])


def main():
    o, r = load(sys.argv[1]), load(sys.argv[2])
    po, pr = phases(o), phases(r)
    lines = [f'# flow diff: {sys.argv[1]} vs {sys.argv[2]}', '',
             '| # | phase | original frames | remaster frames | MV_OK original | MV_OK remaster |', '|---|---|---|---|---|---|']
    exact = 0
    for k in range(max(len(po), len(pr))):
        a = po[k] if k < len(po) else None
        b = pr[k] if k < len(pr) else None
        same = a and b and a[0] == b[0] and (a[1] == b[1] or a[0] in (0, 3))
        exact += bool(same)
        lines.append(f"| {k} | {a[0] if a else '-'}/{b[0] if b else '-'} | {a[1] if a else '-'} | {b[1] if b else '-'} | "
                     f"{fmt_runs(runs([x['mvok'] for x in a[2]])) if a else '-'} | "
                     f"{fmt_runs(runs([x['mvok'] for x in b[2]])) if b else '-'} |" + ('' if same else ' DIFF'))
    lines += ['', f'phases matching (length; phase 3 = any length): {exact} / {max(len(po), len(pr))}', '']
    mm = 0; mt = 0
    for k in range(min(len(po), len(pr))):
        a, b = po[k], pr[k]
        if a[0] == 3 or a[0] != b[0]: continue
        for i in (0, 1):
            ra, rb = motion_runs(a[2], i), motion_runs(b[2], i)
            same = ra == rb
            mt += 1; mm += same
            lines.append(f"- phase {a[0]} (#{k}) P{i + 1}: {'SAME' if same else 'DIFF'}")
            lines.append(f"  - original: {fmt_runs(ra)}")
            if not same: lines.append(f"  - remaster: {fmt_runs(rb)}")
    lines += ['', f'motion runs identical in phases 1/2/4/5: {mm} / {mt}']
    txt = '\n'.join(lines)
    print(txt)
    if len(sys.argv) > 3: open(sys.argv[3], 'w').write(txt + '\n')


if __name__ == '__main__':
    main()
