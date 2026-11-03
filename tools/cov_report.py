#!/usr/bin/env python3
"""fx-cov: the per-tape coverage table (docs/COVERAGE.md) from fidelity_run.py diff reports.
  FID_OUT=dir cov_report.py [TAPE...]    markdown rows: tape, fighters, stage, frames (orig / rem), per-field match %
                                         (P1 / P2), the first divergence (earliest state / motion / position frame)"""
import glob, json, os, sys
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + '/'
sys.path.insert(0, REPO + 'tools')
import tapes
D = './dumps/fidelity/'
OUTD = os.environ.get('FID_OUT', D).rstrip('/') + '/'
F = ['st', 'mot', 'fr', 'x', 'y', 'z', 'ang', 'hp', 'gems']


def first(pr):
    c = [(pr[f]['first'], f) for f in ('st', 'mot', 'x', 'y', 'z', 'hp', 'gems') if pr[f]['first']]
    if not c: return None
    (k, a, b), f = min(c, key=lambda t: t[0][0])
    return k, f, a, b


def row(t):
    j = json.load(open(OUTD + f'reports/{t}.json'))
    m = tapes.meta(REPO + f'game/tests/tapes/{t}.tape') if os.path.exists(REPO + f'game/tests/tapes/{t}.tape') else {}
    om = json.load(open(D + f'o_{t}.meta.json')) if os.path.exists(D + f'o_{t}.meta.json') else {}
    pr = j['players']
    cells = ['/'.join(f"{pr[i][f]['match'] * 100:.0f}" for i in range(2)) for f in F]
    fd = [first(pr[i]) for i in range(2)]
    fdtxt = '; '.join(f"P{i + 1} f{d[0]} {d[1]} {d[2]}->{d[3]}" for i, d in enumerate(fd) if d) or 'none'
    allpass = all(pr[i][f]['match'] == 1.0 for i in range(2) for f in ('st', 'mot', 'x', 'z', 'hp', 'gems'))
    fr = f"{j.get('frames_orig', j['frames'])}/{j.get('frames_rem', j['frames'])}"
    return (f"| {t} | {m.get('p1', '?')} v {m.get('p2', '?')} | {om.get('stage', '?')} | {fr} | " + ' | '.join(cells) +
            f" | {fdtxt} | {'PASS' if allpass else 'FAIL'} |"), j


def main(names):
    if not names: names = sorted(os.path.basename(p)[:-5] for p in glob.glob(OUTD + 'reports/*.json') if '.' not in os.path.basename(p)[:-5] and 'summary' not in p)
    print('| tape | P1 v P2 | stage | frames o/r | ' + ' | '.join(f + ' %' for f in F) + ' | first divergence | verdict |')
    print('|' + '---|' * (len(F) + 6))
    for t in names:
        try: print(row(t)[0])
        except FileNotFoundError: print(f'| {t} | - | - | - | ' + ' | '.join('-' for _ in F) + ' | no report | - |')


if __name__ == '__main__':
    main(sys.argv[1:])
