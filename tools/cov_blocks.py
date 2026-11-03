#!/usr/bin/env python3
"""fx-cov: per-block diff of a coverage tape. A block = the frames from one '@place' row to the next (the stage tapes
start every run / jump / attack block from the same placement on both sides, so each block is its own measurement).
  FID_OUT=dir cov_blocks.py TAPE        per block: comment, frames, P1 / P2 match % (st, mot, x, z, y, hp, gems), the first
                                        divergence (frame in the block, field, orig -> rem, the original's x/y/z there)"""
import json, os, sys
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + '/'
sys.path.insert(0, REPO + 'tools')
import tapes, fidelity_diff as FD
D = './dumps/fidelity/'
OUTD = os.environ.get('FID_OUT', D).rstrip('/') + '/'
F = ('st', 'mot', 'x', 'z', 'y', 'hp', 'gems')
VERBOSE = os.environ.get('V') == '1'


def blocks(src):
    """[(first frame, comment)] from the tape source: a block starts at each run of @place rows."""
    out, n, cmt, pend = [(0, 'start')], 0, '', False
    for ln in open(src):
        s = ln.strip()
        if s.startswith('#'):
            cmt = s.lstrip('# ').strip(); continue
        body = s.split('#')[0].strip()
        if not body: continue
        if body.startswith('@'):
            if body.startswith('@place') and not pend:
                out.append((n + 1, cmt)); pend = True   # row n is logged before its @place: measure from n + 1
            continue
        pend = False
        n += len(tapes.parse(body))
    return out


def main(t):
    o, r = FD.load(D + f'o_{t}.jsonl'), FD.load(OUTD + f'r_{t}.jsonl')
    bl = blocks(REPO + f'game/tests/tapes/{t}.tape')
    n = min(len(o), len(r))
    res = []
    for k, (a, cmt) in enumerate(bl):
        b = bl[k + 1][0] if k + 1 < len(bl) else n
        b = min(b, n)
        if b <= a: continue
        row = {'block': k, 'from': a, 'to': b, 'what': cmt, 'p': []}
        for i in range(2):
            m, first = {}, None
            for f in F:
                ok = 0
                for j in range(a, b):
                    x, y = o[j]['p'][i].get(f), r[j]['p'][i].get(f)
                    if FD.same(f, x, y): ok += 1
                    elif first is None or j < first[0]:
                        first = (j, f, x, y, [o[j]['p'][i][q] for q in ('x', 'y', 'z')])
                m[f] = round(ok / (b - a) * 100)
            row['p'].append({'match': m, 'first': first})
        for i in range(2):   # states / motions one side has in this block and the other not; where the run ended
            so = {(o[j]['p'][i]['st'], o[j]['p'][i]['kind'], o[j]['p'][i]['mot']) for j in range(a, b)}
            sr = {(r[j]['p'][i]['st'], r[j]['p'][i]['kind'], r[j]['p'][i]['mot']) for j in range(a, b)}
            e = min(a + 89, b - 1)
            po, pr = o[e]['p'][i], r[e]['p'][i]
            row['p'][i]['only_orig'] = sorted(so - sr); row['p'][i]['only_rem'] = sorted(sr - so)
            row['p'][i]['run_end'] = {'orig': [po[q] for q in ('x', 'y', 'z', 'st')], 'rem': [pr[q] for q in ('x', 'y', 'z', 'st')],
                                      'd_cm': round(((po['x'] - pr['x']) ** 2 + (po['y'] - pr['y']) ** 2 + (po['z'] - pr['z']) ** 2) ** 0.5, 1)}
        res.append(row)
        fd = '; '.join(f"P{i + 1} +{p['first'][0] - a} {p['first'][1]} {p['first'][2]}->{p['first'][3]} at {p['first'][4]}"
                       for i, p in enumerate(row['p']) if p['first'])
        print(f"{k:2d} f{a}-{b} {cmt[:60]:60s} P1 " + ' '.join(f"{f}{row['p'][0]['match'][f]}" for f in F) +
              ' | P2 ' + ' '.join(f"{f}{row['p'][1]['match'][f]}" for f in F) + f' | {fd or "same"}')
        if VERBOSE:
            for i in range(2):
                p = row['p'][i]
                print(f"     P{i + 1} +89: orig {p['run_end']['orig']} rem {p['run_end']['rem']} d {p['run_end']['d_cm']} cm;"
                      f" only orig {[f's{x}k{y}/{z}' for x, y, z in p['only_orig']][:8]} only rem {[f's{x}k{y}/{z}' for x, y, z in p['only_rem']][:8]}")
    json.dump(res, open(OUTD + f'reports/{t}.blocks.json', 'w'), indent=1)


if __name__ == '__main__':
    for t in sys.argv[1:]: main(t)
